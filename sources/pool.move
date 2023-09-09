// @Authors - JMVC <> Thouny
// This contract manages the minting/burning of iSui, iSUIP, and iSUIY
// ISsui is a share of the total SUI principal + rewards this module owns
// iSUIP is always 1 SUI as it represents the principal owned by this module
// iSUIY represents the yield component of a iSUIP
module interest_lsd::pool { 
  use std::vector;
  use std::option;

  use sui::transfer;
  use sui::sui::SUI;
  use sui::event::emit;
  use sui::table::{Self, Table};
  use sui::coin::{Self, Coin};
  use sui::vec_set::{Self, VecSet};
  use sui::object::{Self, UID, ID};
  use sui::tx_context::{Self, TxContext};
  use sui::linked_table::{Self, LinkedTable};

  use sui_system::staking_pool::{Self, StakedSui};
  use sui_system::sui_system::{Self, SuiSystemState};

  use interest_lsd::admin::AdminCap;
  use interest_lsd::rebase::{Self, Rebase};
  use interest_lsd::math::{fmul, scalar};
  use interest_lsd::semi_fungible_asset::SemiFungibleAsset;
  use interest_lsd::isui::{Self, ISUI, InterestSuiStorage};
  use interest_lsd::sui_yield::{Self, SuiYield, SuiYieldStorage};
  use interest_lsd::staking_pool_utils::{calc_staking_pool_rewards};
  use interest_lsd::sui_principal::{Self, SuiPrincipalStorage, SUI_PRINCIPAL};
  use interest_lsd::fee_utils::{new as new_fee, calculate_fee_percentage, set_fee, Fee};
  
  // ** Constants

  // StakedSui objects cannot be split to below this amount.
  const MIN_STAKING_THRESHOLD: u64 = 1_000_000_000; // 1 

  // ** Errors

  const EInvalidFee: u64 = 0; // All values inside the Fees Struct must be equal or below 1e18 as it represents 100%
  const EInvalidStakeAmount: u64 = 1; // Users need to stake more than 1 MIST as the sui_system will throw 0 value stakes
  const EInvalidUnstakeAmount: u64 = 2; // The sender tried to unstake more than he is allowed 
  const ETooEarly: u64 = 3; // User tried to redeem assets before their maturity
  const EInvalidSplitAmount: u64 = 4; // The user tried to split with an invalid amount, either 0 or more than the SFA contains
  const EInvalidMaturity: u64 = 6; // Sender tried to create a bond with a maturity that is not whitelisted
  const EOutdatedMaturity: u64 = 7; // Sender tried to create a bond with an old maturity
  const EMistmatchedSlots: u64 = 8; // Sender tried to call a bond with SFAs with different slots
  const EMistmatchedValues: u64 = 8; // Sender did not provide the same quantity of Yield and Principal
  const EInvalidBackupMaturity: u64 = 9; // Sender tried to abuse the maturity 

  // ** Structs

  // This struct compacts the data sent to burn_isui
  // We will remove the {principal} amount of StakedSui from the {validator_address} stored at staked_sui_table with the key {epoch}
  struct BurnValidatorPayload has drop, store {
    epoch: u64,
    validator_address: address,
    principal: u64
  }

  struct ValidatorData has key, store {
    id: UID, // front end to grab and display data,
    staking_pool_id: ID, // The ID of the Validator's {StakingPool}
    staked_sui_table: LinkedTable<u64, StakedSui>, // activation_epoch => StakedSui
    total_principal: u64 // Total amount of StakedSui principal deposited in this validator
  }

  // Shared Object
  // Unfortunately, we cannot fully exploit Sui's concurrency model because we need our LSD Coins to reflect the rewards accrued
  // This allows users to instantly to stake Sui by buying this coin without having to go through the process
  // This also makes Coins omnichannel and a user in Ethereum can buy the coin and instantly became a Sui Staker
  // Sui StakingV3 module will have a bonding period, LSDs will be a great way to exit immediately
  struct PoolStorage has key {
    id: UID,
    pool: Rebase, // This struct holds the total shares of ISUI and the total SUI (Principal + Rewards). Rebase {base: ISUI total supply, elastic: total Sui}
    last_epoch: u64, // Last epoch that pool was updated
    validators_table: LinkedTable<address, ValidatorData>, // We need a linked table to iterate through all validators once every epoch to ensure all pool data is accurate
    total_principal: u64, // Total amount of StakedSui principal deposited in Interest LSD Package
    fee: Fee, // Holds the data to calculate the stake fee
    dao_coin: Coin<ISUI>, // Fees collected by the protocol in ISUI
    whitelist_validators: VecSet<address>,
    whitelist_maturities: VecSet<u64>,
    exchange_rates: Table<u64, u64>, // 1Sui -> Sui Exchange rate
  }

  // ** Events

  struct MintISui has copy, drop {
    sender: address,
    sui_amount: u64,
    isui_amount: u64,
    validator: address
  }

  struct BurnISui has copy, drop {
    sender: address,
    sui_amount: u64,
    isui_amount: u64,
  }

  struct MintStrippedBond has copy, drop {
    sender: address,
    sui_amount: u64,
    sui_yield_id: ID,
    sui_principal_id: ID,
    validator: address
  }

  struct CallBond has copy, drop {
    sender: address,
    sui_amount: u64,
    validator: address,
    maturity: u64    
  }

  struct BurnSuiPrincipal has copy, drop {
    sender: address,
    sui_amount: u64
  }

  struct ClaimYield has copy, drop {
    sender: address,
    sui_yield_id: ID,
    sui_amount: u64,   
  }

  // Emitted when the DAO updates the fee
  struct NewFee has copy, drop {
    base: u256,
    kink: u256,
    jump: u256
  }

  // Emitted when the DAO withdraws some rewards
  // Most likely to cover the {updatePools} calls
  struct DaoWithdraw<phantom T> has copy, drop {
    sender: address,
    amount: u64
  }

  struct AddWhitelist has copy, drop {
    validator: address
  }

  struct RemoveWhitelist has copy, drop {
    validator: address
  }

  fun init(ctx: &mut TxContext) {
    // Share the PoolStorage Object with the Sui network
    transfer::share_object(
        PoolStorage {
        id: object::new(ctx),
        pool: rebase::new(),
        last_epoch: 0,
        validators_table: linked_table::new(ctx),
        total_principal: 0,
        fee: new_fee(),
        dao_coin: coin::zero<ISUI>(ctx),
        whitelist_validators: vec_set::empty(),
        whitelist_maturities: vec_set::empty(),
        exchange_rates: table::new(ctx)
      }
    );
  }

  // @dev It returns the exchange rate from ISUI to SUI
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param isui_amount The amount of ISUI
  * @return the exchange rate
  */
  public fun get_exchange_rate_isui_to_sui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage, 
    isui_amount: u64,
    ctx: &mut TxContext
  ): u64 {
    update_pool(wrapper, storage, ctx);
    rebase::to_elastic(&storage.pool, isui_amount, false)
  }

  // @dev It returns the exchange rate from SUI to ISUI
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sui_amount The amount of SUI
  * @param return the exchange rate
  */
  public fun get_exchange_rate_sui_to_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage, 
    sui_amount: u64,
    ctx: &mut TxContext
  ): u64 {
    update_pool(wrapper, storage, ctx);
    rebase::to_base(&storage.pool, sui_amount, false)
  }

  // @dev It returns the Sui value of the {sfa}
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sfa The SuiYield
  * @param maturity the backup maturity
  * @return the exchange rate
  */
  public fun quote_sui_yield(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage, 
    sfa: &SuiYield,
    maturity: u64,
    ctx: &mut TxContext
  ): u64 {

    // We update the pool to make sure the rewards are up to date
    update_pool(wrapper, storage, ctx);

    quote_sui_yield_logic(storage, sfa, maturity, ctx)
  }

  // @dev Utility function to create {BurnValidatorPayload} Object for other modules
  /*
  * @param validator_address The validator to which we will unstake
  * @param epoch The action_epoch of the {StakedSui} we will unstake
  * @param principal How much of the {StakedSui} to unstake
  * @return {BurnValidatorPayload} to use on {burn_isui}, {burn_interest_staked_sui} and {burn_isui_yc}
  */
  public fun create_burn_validator_payload(validator_address: address, epoch: u64, principal: u64): BurnValidatorPayload {
    BurnValidatorPayload {
      validator_address,
      epoch, 
      principal
    }
  }

  // @dev This function costs a lot of gas and must be called before any interaction with Interest LSD because it updates the pool. The pool is needed to ensure all 3 Coins' exchange rate is accurate.
  // Anyone can call this function
  // It will ONLY RUN ONCE per epoch
  // Dev Team will call as soon as a new epoch starts so the first user does not need to incur this cost
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  */
  entry public fun update_pool(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    ctx: &mut TxContext,
  ) {
    // Save current epoch -1 in memory
    // Rewards are given at the end of each epoch
    // If users withdraw coins in the current epoch the rewards will change, therefore, we only calculate rewards once they are fully finalized
    let epoch = tx_context::epoch(ctx) - 1;

    //If the function has been called this epoch, we do not need to do anything else
    // If there are no shares in the pool, it means there is no sui being staked. So there are no updates
    if (epoch == storage.last_epoch || rebase::base(&storage.pool) == 0) return;

    let total_rewards = 0;

    // Get the first validator in the linked_table
    let next_validator = linked_table::front(&storage.validators_table);
    
    // We iterate through all validators. This can grow to 1000+
    while (option::is_some(next_validator)) {
      // Save the validator address in memory. We first check that it exists above.
      let validator_address = *option::borrow(next_validator);

      // Get the validator data
      let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

      let pool_exchange_rates = sui_system::pool_exchange_rates(wrapper, &validator_data.staking_pool_id);
      let current_exchange_rate = table::borrow(pool_exchange_rates, epoch);

      // If the validator does not have any sui staked, we to the next validator
      if (validator_data.total_principal != 0) {
        // We calculate the total rewards we will get based on our current principal staked in the validator

        let next_key = linked_table::front(&validator_data.staked_sui_table);

        while (option::is_some(next_key)) {
          let activation_epoch = *option::borrow(next_key);
          
          let staked_sui = linked_table::borrow(&validator_data.staked_sui_table, activation_epoch);
          
          // We only update the rewards if the {epoch} is greater than the {activation_epoch}
          // Otherwise, these sui have not accrued any rewards
          // We update the total rewards
          if (epoch >= activation_epoch)
            total_rewards = total_rewards + calc_staking_pool_rewards(
              table::borrow(pool_exchange_rates, activation_epoch),
              current_exchange_rate,
              staking_pool::staked_sui_amount(staked_sui)
            );

          next_key = linked_table::next(&validator_data.staked_sui_table, activation_epoch);
        };
      };
      
      // Point the next_validator to the next one
      next_validator = linked_table::next(&storage.validators_table, validator_address);
    };

    // We update the total Sui (principal + rewards) 
    rebase::set_elastic(&mut storage.pool, total_rewards + storage.total_principal);
    // Update the last_epoch
    storage.last_epoch = epoch;
    // We save the epoch => exchange rate for iSui => Sui
    // Today's exchange rate is always yesterdays
    table::add(
      &mut storage.exchange_rates, 
      epoch + 1, 
      rebase::to_elastic(&storage.pool, MIN_STAKING_THRESHOLD, false)
    );
  }

  // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
  * @param asset The Sui Coin, the sender wishes to stake
  * @param validator_address The Sui Coin will be staked in this validator
  * @return Coin<ISUI> in exchange for the Sui deposited
  */
  public fun mint_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    asset: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<ISUI> {
    let sui_amount = coin::value(&asset);
    
    // mint_isui_logic will update the pool
    let shares = mint_isui_logic(wrapper, storage, asset, validator_address, ctx);

    let shares_to_mint = if (is_whitelisted(storage, validator_address)) {
      shares
    } else {
      let validator_principal = linked_table::borrow(&storage.validators_table, validator_address).total_principal;
      charge_isui_mint(
        storage, 
        interest_sui_storage, 
        validator_principal, 
        shares, 
        ctx
      )
    };

    emit(MintISui { validator: validator_address, sender: tx_context::sender(ctx), sui_amount, isui_amount: shares_to_mint });

    // Mint iSUI to the caller
    isui::mint(interest_sui_storage, shares_to_mint, ctx)
  }

  // @dev This function burns ISUI and unstake Sui 
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
  * @param validator_payload A vector containing the information about which StakedSui to unstake
  * @param asset The iSui Coin, the sender wishes to burn
  * @param validator_address The validator is to re-stake any remaining Sui if any
  * @return Coin<SUI> in exchange for the iSui burned
  */
  public fun burn_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    validator_payload: vector<BurnValidatorPayload>,
    asset: Coin<ISUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);

    let isui_amount = coin::value(&asset);

    // Update the pool 
    // Remove the shares
    // Burn the iSUI
    let sui_value_to_return = rebase::sub_base(&mut storage.pool, isui::burn(interest_sui_storage, asset, ctx), false);

    let (staked_sui_vector, total_principal_unstaked) = remove_staked_sui(storage, validator_payload, ctx);

    // Sender must Unstake a bit above his principal because it is possible that the unstaked left over rewards wont meet the min threshold
    // The user withdraw 1 Sui Above what he wishes to withdraw to guarantee that we can re-stake the rewards
    // If we allow more than 1 Sui, a user can grief the module and force a re-stake of all {StakedSui} preventing the module ot earn rewards
    assert!((total_principal_unstaked - MIN_STAKING_THRESHOLD) == sui_value_to_return, EInvalidUnstakeAmount);

    emit(BurnISui { sender: tx_context::sender(ctx), sui_amount: sui_value_to_return, isui_amount });

    // Unstake Sui
    unstake_staked_sui(wrapper, storage, staked_sui_vector, validator_address, sui_value_to_return, ctx)
  }

  // @dev This function stakes Sui in a validator chosen by the sender and mints a stripped bond (SuiPrincipal + Sui Yield). 
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
  * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to mint.
  * @param sui_yield_storage The shared object of Sui Yield, it contains the treasury_cap. We need it to mint.
  * @param asset The Sui Coin, the sender wishes to stake
  * @param validator_address The Sui Coin will be staked in this validator
  * @param maturity The intended maturity of the bond
  * @return (COIN<Sui Principal>, SuiYield)
  */
  public fun mint_stripped_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    asset: Coin<SUI>,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ):(SemiFungibleAsset<SUI_PRINCIPAL>, SuiYield) {
    // It is a whitelisted maturity
    assert!(vec_set::contains(&storage.whitelist_maturities, &EInvalidMaturity), EInvalidMaturity);
    
    let epoch = tx_context::epoch(ctx);
    assert!(epoch > maturity, EOutdatedMaturity);

    let sui_amount = coin::value(&asset);

    // mint_isui_logic will update the pool
    let sfa_yield = sui_yield::new( 
      sui_yield_storage,
      (epoch as u256),
      sui_amount,
      mint_isui_logic(wrapper, storage,asset, validator_address, ctx),
      ctx
    );

    let sui_amount = if (is_whitelisted(storage, validator_address)) { 
      sui_amount 
    } else {
      let validator_principal = linked_table::borrow(&storage.validators_table, validator_address).total_principal;
      charge_interest_staked_sui_mint(
        storage, 
        interest_sui_storage, 
        validator_principal, 
        sui_amount, 
        ctx        
      )
    };

    let sfa_principal = sui_principal::new(sui_principal_storage, (epoch as u256), sui_amount, ctx);

    emit(MintStrippedBond { 
      sender: tx_context::sender(ctx), 
      sui_amount, 
      sui_principal_id: object::id(&sfa_principal),
      sui_yield_id: object::id(&sfa_yield),
      validator: validator_address 
    });

    (
      sfa_principal,
      sfa_yield
    ) 
  } 

  // @dev This function allows the caller to call the stripped bond. It rquires both components to turn in to a bond
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to mint.
  * @param sui_yield_storage The shared object of Sui Yield, it contains the treasury_cap. We need it to mint.
  * @param validator_payload A vector containing the information about which StakedSui to unstake
  * @param sfa_principal The residue portion of the bond
  * @param sfa_yield The yield portion of the bond
  * @param validator_address The Sui Coin will be staked in this validator
  * @param maturity Back up maturity in case we missed an pool update call (should not happen)
  * @return Coin<SUI> in exchange for the Sui Principal burned
  */
  public fun call_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    validator_payload: vector<BurnValidatorPayload>,
    sfa_principal: SemiFungibleAsset<SUI_PRINCIPAL>,
    sfa_yield: SuiYield,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    let slot = (sui_yield::slot(&sfa_yield) as u64);
    
    // They must be with the same slot
    assert!((slot as u256) == sui_principal::slot(&sfa_principal), EMistmatchedSlots);
    // They must have the same value
    assert!(sui_yield::value(&sfa_yield) == sui_principal::value(&sfa_principal), EMistmatchedValues);

    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);

    // Destroy both assets
    // Calculate how much Sui they are worth
    let sui_value_to_return = quote_sui_yield_logic(storage, &sfa_yield, maturity, ctx) + sui_principal::burn_destroy(sui_principal_storage, sfa_principal);
    sui_yield::burn_destroy(sui_yield_storage, sfa_yield);

    emit(CallBond { 
      sui_amount: 
      sui_value_to_return, 
      sender: tx_context::sender(ctx), 
      maturity: slot,
      validator: validator_address
    });

    let (staked_sui_vector, total_principal_unstaked) = remove_staked_sui(storage, validator_payload, ctx);

    // Sender must Unstake a bit above his principal because it is possible that the unstaked left over rewards wont meet the min threshold
    assert!((total_principal_unstaked - MIN_STAKING_THRESHOLD) == sui_value_to_return, EInvalidUnstakeAmount);

    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_value_to_return, false);

    // Unstake Sui
    unstake_staked_sui(wrapper, storage, staked_sui_vector, validator_address, sui_value_to_return, ctx)
  }

  // @dev This function burns Sui Principal in exchange for SUI at 1:1 rate
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to burn Sui Principal
  * @param validator_payload A vector containing the information about which StakedSui to unstake
  * @param asset The Sui Principal, the sender wishes to burn
  * @param validator_address The validator to re stake any remaining Sui if any
  * @return Coin<SUI> in exchange for the Sui Principal burned
  */
  public fun burn_sui_principal(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    validator_payload: vector<BurnValidatorPayload>,
    asset: SemiFungibleAsset<SUI_PRINCIPAL>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    assert!(tx_context::epoch(ctx) > (sui_principal::slot(&asset) as u64), ETooEarly);

    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);

    // 1 Sui Principal is always 1 SUI
    // Burn the Sui Principal
    let sui_value_to_return = sui_principal::burn_destroy(sui_principal_storage, asset);

    let (staked_sui_vector, total_principal_unstaked) = remove_staked_sui(storage, validator_payload, ctx);

    // Sender must Unstake a bit above his principal because it is possible that the unstaked left over rewards wont meet the min threshold
    assert!((total_principal_unstaked - MIN_STAKING_THRESHOLD) == sui_value_to_return, EInvalidUnstakeAmount);

    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_value_to_return, false);

    emit(BurnSuiPrincipal { sui_amount: sui_value_to_return, sender: tx_context::sender(ctx) });

    // Unstake Sui
    unstake_staked_sui(wrapper, storage, staked_sui_vector, validator_address, sui_value_to_return, ctx)
  }

  // @dev This function allows a sender to claim his accrued yield
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator_payload A vector containing the information about which StakedSui to unstake
  * @param sfa_yield The SuiYield to burn in exchange for rewards
  * @param validator_address The validator to re stake any remaining Sui if any
  * @param maturity The back up maturity in case we missed a {update_pool} call
  * @return (SuiYield, Coin<SUI>) Returns the original asset and the yield to the sender
  */
  public fun claim_yield(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    validator_payload: vector<BurnValidatorPayload>,
    sfa_yield: SuiYield,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ): (SuiYield, Coin<SUI>) {
    
    // Destroy both assets
    // Calculate how much Sui they are worth
    let sui_amount = quote_sui_yield(wrapper, storage, &sfa_yield, maturity, ctx);

    // Consider yield paid
    sui_yield::add_rewards_paid(&mut sfa_yield, sui_amount);

    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_amount, false);

    let (staked_sui_vector, total_principal_unstaked) = remove_staked_sui(storage, validator_payload, ctx);

    // Sender must Unstake more than his principal to ensure that the leftover is above the threshold of 1 Sui
    assert!((total_principal_unstaked - MIN_STAKING_THRESHOLD) == sui_amount, EInvalidUnstakeAmount);

    emit(ClaimYield { sui_yield_id: object::id(&sfa_yield), sui_amount, sender: tx_context::sender(ctx) });

    // Unstake Sui
    (sfa_yield, unstake_staked_sui(wrapper, storage, staked_sui_vector, validator_address, sui_amount, ctx))
  }

  // ** Functions to handle Whitelist validators

  // Checks if a validator is whitelisted (pays no fee)
  /*
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator The address of the validator
  * @return bool true if it is whitelisted
  */
  public fun is_whitelisted(storage: &PoolStorage, validator: address): bool {
    vec_set::contains(&storage.whitelist_validators, &validator)
  }

  // Whitelists a validator to pay no fee
  /*
  * @param _ The Admin Cap
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator The address of the validator
  */
  public entry fun add_whitelist(_: &AdminCap, storage: &mut PoolStorage, validator: address) {
    if (is_whitelisted(storage, validator)) return;

    vec_set::insert(&mut storage.whitelist_validators, validator);
    emit(AddWhitelist { validator });
  }

  // Removes a validator from the whitelist
  /*
  * @param _ The Admin Cap
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator The address of the validator
  */
  public entry fun remove_whitelist(_: &AdminCap, storage: &mut PoolStorage, validator: address) {
    if (!is_whitelisted(storage, validator)) return;

    vec_set::remove(&mut storage.whitelist_validators, &validator);
    emit(RemoveWhitelist { validator });
  }

  // ** Admin Functions

  // @dev This function safely updates the fees. It will throw if you pass values higher than 1e18.  
  /*
  * @param _: The AdminCap
  * @param storage: The Pool Storage Shared Object (this module)
  * @param base: The new base
  * @param kink: The new kink
  * @param jump The new jump
  */
  entry public fun update_fee(
    _: &AdminCap,
    storage: &mut PoolStorage, 
    base: u256, 
    kink: u256, 
    jump: u256
  ) {
    let max = scalar();
    // scalar represents 100% - the protocol does not allow a fee higher than that.
    assert!(max >= base && max >= kink && max >= jump, EInvalidFee);

    // Update the fee values
    set_fee(&mut storage.fee, base, kink, jump);

    // Emit event
    emit(NewFee { base, kink, jump });
  }

  // @dev This function allows the DAO to withdraw fees.
  /*
  * @param _: The AdminCap
  * @param storage: The Pool Storage Shared Object (this module)
  * @param amount: The value of fees to withdraw
  * @return the fees in Coin<ISUI>
  */
  public fun withdraw_fees(
    _: &AdminCap,
    storage: &mut PoolStorage, 
    amount: u64,
    ctx: &mut TxContext
  ): Coin<ISUI> {
    
    // Emit the event
    emit(DaoWithdraw<ISUI> {amount, sender: tx_context::sender(ctx) });

    // Split the Fees and send the desired amount
    coin::split(&mut storage.dao_coin, amount, ctx)
  }

  // ** CORE OPERATIONS

  // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
  * @param asset The Sui Coin, the sender wishes to stake
  * @param validator_address The Sui Coin will be staked in this validator
  * @return Coin<ISUI> in exchange for the Sui deposited
  */
  fun mint_isui_logic(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    asset: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,    
  ): u64 {
    // Save the value of Sui being staked in memory
    let stake_value = coin::value(&asset);

    // Will save gas since the sui_system will throw
    assert!(stake_value >= MIN_STAKING_THRESHOLD, EInvalidUnstakeAmount);
    
    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);
  
    // Stake Sui 
    // We need to stake Sui before registering the validator to have access to the pool_id
    let staked_sui = sui_system::request_add_stake_non_entry(wrapper, asset, validator_address, ctx);

    // Register the validator once in the linked_list
    safe_register_validator(storage, staking_pool::pool_id(&staked_sui), validator_address, ctx);

    // Save the validator data in memory
    let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

    // Store the Sui in storage
    store_staked_sui(validator_data, staked_sui);

    // Update the total principal in this entire module
    storage.total_principal = storage.total_principal + stake_value;
    // Update the total principal staked in this validator
    validator_data.total_principal = validator_data.total_principal + stake_value;

    // Update the Sui Pool 
    // We round down to give the edge to the protocol
    rebase::add_elastic(&mut storage.pool, stake_value, false)    
  }

  // @dev This function stores StakedSui with the same {activation_epoch} on a {LinkedTable}
  /*
  * @param validator_data: The Struct Data for the validator where we will deposit the Sui
  * @param staked_sui: The StakedSui Object to store
  */
  fun store_staked_sui(validator_data: &mut ValidatorData, staked_sui: StakedSui) {
      let activation_epoch = staking_pool::stake_activation_epoch(&staked_sui);

      // If we already have Staked Sui with the same validator and activation epoch saved in the table, we will merge them
      if (linked_table::contains(&validator_data.staked_sui_table, activation_epoch)) {
        // Merge the StakedSuis
        staking_pool::join_staked_sui(
          linked_table::borrow_mut(&mut validator_data.staked_sui_table, activation_epoch), 
          staked_sui
        );
      } else {
        // If there is no StakedSui with the {activation_epoch} on our table, we add it.
        linked_table::push_back(&mut validator_data.staked_sui_table, activation_epoch, staked_sui);
      };
  }
  

  // @dev This function safely removes Staked Sui from our storage
  /*
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator_payload A vector containing the information about which StakedSui to unstake
  * @return (Vector of Staked Sui, total principal of Staked Sui Removed)
  */
  fun remove_staked_sui(
      storage: &mut PoolStorage,
      validator_payload: vector<BurnValidatorPayload>, 
      ctx: &mut TxContext
    ): (vector<StakedSui>, u64) {
    
    let length = vector::length(&validator_payload);
    let i = 0;
    let total_principal_unstaked = 0;
    let staked_sui_vector = vector::empty<StakedSui>();

    while (i < length) {

      let payload = vector::borrow(&validator_payload, i);

      // Save the validator data in memory
      let validator_data = linked_table::borrow_mut(&mut storage.validators_table, payload.validator_address);

    
      // Remove the StakedSui from the {LinkedTable}
      // It is important that we shrink this table to make the {update_pool} run less iterations
      let staked_sui = linked_table::remove(&mut validator_data.staked_sui_table, payload.epoch);

      let staked_sui_amount = staking_pool::staked_sui_amount(&staked_sui);

      // We do not need to split the Sui so we can simply save it in the vector
      if (staked_sui_amount == payload.principal) {
        vector::push_back(&mut staked_sui_vector, staked_sui);     
      } else {
        // We need to split the StakedSui
        // Save the desired amount in the vector
        // Store the remaining Sui in the Storage
        vector::push_back(&mut staked_sui_vector, staking_pool::split(&mut staked_sui, payload.principal, ctx));
        store_staked_sui(validator_data, staked_sui);
      };

      // Update the validator data to reflect the unstaked Sui
      validator_data.total_principal =  validator_data.total_principal - payload.principal;
      // Update the total principal unstaked to make sure we do not unstake too much Sui and lose unnecessary rewards
      total_principal_unstaked = total_principal_unstaked + payload.principal;   

      i = i + 1;
    };
    storage.total_principal = storage.total_principal - total_principal_unstaked;
    (staked_sui_vector, total_principal_unstaked)
  }

  // @dev This function unstakes StakedSui from the validators
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param staked_sui_vector The vector of StakedSui to unstake
  * @param validator_address The validator is to re-stake any remaining Sui if any
  * @param sui_value_to_return The desired amount of Sui to unstake
  * @return Coin<SUI> The unstaked Sui
  */
  fun unstake_staked_sui(
    wrapper: &mut SuiSystemState, 
    storage: &mut PoolStorage,
    staked_sui_vector: vector<StakedSui>, 
    validator_address: address,
    sui_value_to_return: u64,
    ctx: &mut TxContext
  ): Coin<SUI> {
    let total_sui_coin = coin::zero<SUI>(ctx);

    let i = 0;
    let length = vector::length(&staked_sui_vector);

    // Unstake and merge into one coin
    while(i < length) {
      coin::join(&mut total_sui_coin, coin::from_balance(sui_system::request_withdraw_stake_non_entry(wrapper, vector::pop_back(&mut staked_sui_vector), ctx), ctx));
      i = i + 1;
    };

    // This should be empty
    vector::destroy_empty(staked_sui_vector);

    // Split the coin with the right value to repay the user
    let sui_to_return = coin::split(&mut total_sui_coin, sui_value_to_return, ctx);

    // Save the ValidatorData in memory so we can store any remaining Sui
    let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

    let left_over_amount = coin::value(&total_sui_coin);

    // Update the data
    // Rewards will increase the principals
    validator_data.total_principal = validator_data.total_principal + left_over_amount;
    storage.total_principal = storage.total_principal + left_over_amount;

    // Stake the Sui and store the Staked Sui in memory
    store_staked_sui(
      validator_data, 
      sui_system::request_add_stake_non_entry(wrapper, total_sui_coin, validator_address, ctx)
    );

    sui_to_return
  }

  // If there is a fee, it mints iSUi for the Admin
  /*
  * @param storage: The Pool Storage Shared Object (this module)
  * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
  * @param validator_principal The amount of Sui principal deposited to the validator
  * @param shares The amount of iSui being minted
  * @return the amount of ISUI to mint to the sender
  */
  fun charge_isui_mint(
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    validator_principal: u64,
    shares: u64,
    ctx: &mut TxContext
    ): u64 {
    
    // Find the fee % based on the validator dominance and fee parameters.  
    let fee_amount = calc_fee(storage, validator_principal, shares);

    // If the fee is zero, there is nothing else to do
    if (fee_amount == 0) return shares;

    // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
    coin::join(&mut storage.dao_coin, isui::mint(interest_sui_storage, fee_amount, ctx));
    // Return the shares amount to mint to the sender
    shares - fee_amount
  }

    // If there is a fee, it mints iSUi for the Admin
  /*
  * @storage: The Pool Storage Shared Object (this module)
  * @interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
  * @validator_principal The amount of Sui principal deposited to the validator
  * @amount The amount of Interest Sui Staked Amount being minted
  * @return the amount of ISUI to mint to the sender
  */
  fun charge_interest_staked_sui_mint(
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    validator_principal: u64,
    amount: u64,
    ctx: &mut TxContext
    ): u64 {
    
    // Find the fee % based on the validator dominance and fee parameters.  
    let fee_amount = calc_fee(storage, validator_principal, amount);

    // If the fee is zero, there is nothing else to do
    if (fee_amount == 0) return amount;

    // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
    coin::join(&mut storage.dao_coin, isui::mint(
      interest_sui_storage, 
      rebase::to_base(&storage.pool, fee_amount, false), 
      ctx
    ));

    // Return the shares amount to mint to the sender
    amount - fee_amount
  }

  // Core fee calculation logic
  /*
  * @storage: The Pool Storage Shared Object (this module)
  * @validator_principal The amount of Sui principal deposited to the validator
  * @amount The amount being minted
  * @return u64 The fee amount
  */
  fun calc_fee(
    storage: &mut PoolStorage,
    validator_principal: u64,
    amount: u64,
  ): u64 {
    // Find the fee % based on the validator dominance and fee parameters.  
    let fee = calculate_fee_percentage(
      &storage.fee,
      (validator_principal as u256),
      (storage.total_principal as u256)
    );

    // Calculate fee
    (fmul((amount as u256), fee) as u64)
  }

  // @dev Adds a Validator to the linked_list
  /*
  * @storage: The Pool Storage Shared Object (this module)
  * @staking_pool_id: The Id of the {validator_address} StakingPool
  * @validator_address: The address of the validator
  */
  fun safe_register_validator(
    storage: &mut PoolStorage,
    staking_pool_id: ID,
    validator_address: address,
    ctx: &mut TxContext,    
  ) {
    // If the validator is already registered there is nmothing to do.
    if (linked_table::contains(&storage.validators_table, validator_address)) return;
    
    // Add the ValidatorData to the back of the list
    linked_table::push_back(&mut storage.validators_table, validator_address, ValidatorData {
        id: object::new(ctx),
        staked_sui_table: linked_table::new(ctx),
        staking_pool_id,
        total_principal: 0
      }); 
  }

  // @dev It returns the Sui value of the {sfa}. it does not update the pool so careful!
  /*
  * @param storage The Pool Storage Shared Object (this module)
  * @param sfa The SuiYield
  * @return u64 the exchange rate
  */
  fun quote_sui_yield_logic(
    storage: &mut PoolStorage, 
    sfa_yield: &SuiYield,
    maturity: u64,
    ctx: &mut TxContext
  ): u64 {
    let slot = (sui_yield::slot(sfa_yield) as u64);

    let (shares, principal, rewards_paid) = sui_yield::read_data(sfa_yield);

    let shares_value = if (tx_context::epoch(ctx) > slot) {
      // If the user is getting the yield after maturity
      // We need to find the exchange rate at maturity

      // Check if the table has slot exchange rate
      // If it does not we use the back up maturity value
      let exchange_rate = if (table::contains(&storage.exchange_rates, slot)) { 
        *table::borrow(&storage.exchange_rates, slot)
      } else {
        // Back up maturity needs to be before the slot
        assert!(slot > maturity, EInvalidBackupMaturity);
        *table::borrow(&storage.exchange_rates, maturity)
      };

      ((exchange_rate as u256) * (shares as u256) / (MIN_STAKING_THRESHOLD as u256) as u64)
    } else {
      // If it is before maturity - we just read the pool
      rebase::to_elastic(&storage.pool, shares, false)
    };

    let debt = rewards_paid + principal;

    // Remove the principal to find out how many rewards this SFA has accrued
    if (debt >= shares_value) {
      0
    } else {
      shares_value - debt
    }
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }

  #[test_only]
  public fun read_pool_storage(storage: &PoolStorage): (&Rebase, u64, &LinkedTable<address, ValidatorData>, u64, &Fee, &Coin<ISUI>) {
    (
      &storage.pool, 
      storage.last_epoch, 
      &storage.validators_table, 
      storage.total_principal, 
      &storage.fee, 
      &storage.dao_coin
    ) 
  }

  #[test_only]
  public fun read_validator_data(data: &ValidatorData): (&LinkedTable<u64, StakedSui>, u64) {
    (
      &data.staked_sui_table,
      data.total_principal
    )
  }
}
