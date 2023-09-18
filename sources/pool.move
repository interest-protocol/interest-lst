// @Authors - JMVC <> Thouny
// This contract manages the minting/burning of iSui, iSUIP, and iSUIY
// ISsui is a share of the total SUI principal + rewards this module owns
// iSUIP is always 1 SUI as it represents the principal owned by this module
// iSUIY represents the yield component of a iSUIP
module interest_lst::pool { 
  use std::vector;
  use std::option;

  use sui::table;
  use sui::transfer;
  use sui::sui::SUI;
  use sui::event::emit;
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::balance::{Self, Balance};
  use sui::tx_context::{Self, TxContext};
  use sui::linked_table::{Self, LinkedTable};
  use sui_system::staking_pool::{Self, StakedSui};
  use sui_system::sui_system::{Self, SuiSystemState};

  use interest_lst::admin::AdminCap;
  use interest_lst::rebase::{Self, Rebase};
  use interest_lst::math::{fmul, scalar};
  use interest_lst::semi_fungible_token::SemiFungibleToken;
  use interest_lst::isui::{Self, ISUI, InterestSuiStorage};
  use interest_lst::sui_yield::{Self, SuiYield, SuiYieldStorage};
  use interest_lst::staking_pool_utils::{calc_staking_pool_rewards};
  use interest_lst::sui_principal::{Self, SuiPrincipalStorage, SUI_PRINCIPAL};
  use interest_lst::fee_utils::{new as new_fee, calculate_fee_percentage, set_fee, Fee};

  friend interest_lst::review;
  
  // ** Constants

  // StakedSui objects cannot be split to below this amount.
  const MIN_STAKING_THRESHOLD: u64 = 1_000_000_000; // 1 

  // ** Errors

  const EInvalidFee: u64 = 0; // All values inside the Fees Struct must be equal or below 1e18 as it represents 100%
  const EMistmatchedValues: u64 = 1; // Sender did not provide the same quantity of Yield and Principal
  const EInvalidStakeAmount: u64 = 2; // The sender tried to unstake more than he is allowed 
  const ETooEarly: u64 = 3; // User tried to redeem tokens before their maturity
  const EInvalidMaturity: u64 = 4; // Sender tried to create a bond with an outdated maturity
  const EInvalidBackupMaturity: u64 = 5; // Sender tried to abuse the maturity 
  const EMistmatchedSlots: u64 = 6; // Sender tried to call a bond with SFTs with different slots

  // ** Structs

  struct ValidatorData has key, store {
    id: UID, // front end to grab and display data,
    staking_pool_id: ID, // The ID of the Validator's {StakingPool}
    staked_sui_table: LinkedTable<u64, StakedSui>, // activation_epoch => StakedSui
    total_principal: u64 // Total amount of StakedSui principal deposited in this validator
  }

  // Shared Object
  // Unfortunately, we cannot fully exploit Sui's concurrency model because we need our lst Coins to reflect the rewards accrued
  // This allows users to instantly to stake Sui by buying this coin without having to go through the process
  // This also makes Coins omnichannel and a user in Ethereum can buy the coin and instantly became a Sui Staker
  // Sui StakingV3 module will have a bonding period, lsts will be a great way to exit immediately
  struct PoolStorage has key {
    id: UID,
    pool: Rebase, // This struct holds the total shares of ISUI and the total SUI (Principal + Rewards). Rebase {base: ISUI total supply, elastic: total Sui}
    last_epoch: u64, // Last epoch that pool was updated
    validators_table: LinkedTable<address, ValidatorData>, // We need a linked table to iterate through all validators once every epoch to ensure all pool data is accurate
    total_principal: u64, // Total amount of StakedSui principal deposited in Interest lst Package
    fee: Fee, // Holds the data to calculate the stake fee
    dao_coin: Coin<ISUI>, // Fees collected by the protocol in ISUI
    whitelist_validators: vector<address>,
    pool_history: LinkedTable<u64, Rebase>, // Epoch => Pool Data
    dust: Balance<SUI> // If there is less than 1 Sui from unstaking (rewards)
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

  struct UpdatePool has copy, drop {
    rewards: u64,
    principal: u64
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
        whitelist_validators: vector::empty(),
        pool_history: linked_table::new(ctx),
        dust: balance::zero()
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

  // @dev It returns how much Sui a SuiYield can claim
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sft The SuiYield
  * @param maturity the backup maturity
  * @return the exchange rate
  */
  public fun get_pending_yield(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage, 
    sft: &SuiYield,
    maturity: u64,
    ctx: &mut TxContext
  ): u64 {

    // We update the pool to make sure the rewards are up to date
    update_pool(wrapper, storage, ctx);

    get_pending_yield_logic(storage, sft, maturity, ctx)
  }

  // @dev This function costs a lot of gas and must be called before any interaction with Interest lst because it updates the pool. The pool is needed to ensure all 3 Coins' exchange rate is accurate.
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
    // Save the current epoch in memory
    let epoch = tx_context::epoch(ctx);

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
      let validator_data = linked_table::borrow(&storage.validators_table, validator_address);

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
    // We save the epoch => Pool Rebase
    linked_table::push_back(
      &mut storage.pool_history, 
      epoch, 
      storage.pool
    );
    emit(UpdatePool { principal: storage.total_principal, rewards: total_rewards  });
  }

  // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
  * @param token The Sui Coin, the sender wishes to stake
  * @param validator_address The Sui Coin will be staked in this validator
  * @return Coin<ISUI> in exchange for the Sui deposited
  */
  public fun mint_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    token: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<ISUI> {
    let sui_amount = coin::value(&token);
    
    // mint_isui_logic will update the pool
    let shares = mint_isui_logic(wrapper, storage, token, validator_address, ctx);

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
  * @param token The iSui Coin, the sender wishes to burn
  * @param validator_address The address of a validator to stake any leftover Sui
  * @return Coin<SUI> in exchange for the iSui burned
  */
  public fun burn_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    token: Coin<ISUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);

    let isui_amount = isui::burn(interest_sui_storage, token, ctx);

    // Update the pool 
    // Remove the shares
    // Burn the iSUI
    let sui_value_to_return = rebase::sub_base(&mut storage.pool, isui_amount, false);

    emit(BurnISui { sender: tx_context::sender(ctx), sui_amount: sui_value_to_return, isui_amount });

    // Unstake Sui
    remove_staked_sui(wrapper, storage, sui_value_to_return, validator_address, ctx)
  }

  // @dev This function stakes Sui in a validator chosen by the sender and mints a stripped bond (SuiPrincipal + Sui Yield). 
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
  * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to mint.
  * @param sui_yield_storage The shared object of Sui Yield, it contains the treasury_cap. We need it to mint.
  * @param token The Sui Coin, the sender wishes to stake
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
    token: Coin<SUI>,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ):(SemiFungibleToken<SUI_PRINCIPAL>, SuiYield) {
    // It makes no sense to create an expired bond
    assert!(maturity > tx_context::epoch(ctx), EInvalidMaturity);

    let token_amount = coin::value(&token);
    mint_isui_logic(wrapper, storage, token, validator_address, ctx);


    let sui_amount = if (is_whitelisted(storage, validator_address)) { 
      token_amount
    } else {
      let validator_principal = linked_table::borrow(&storage.validators_table, validator_address).total_principal;
      charge_stripped_bond_mint(
        storage, 
        interest_sui_storage, 
        validator_principal, 
        token_amount, 
        ctx        
      )
    };

    let shares_amount = rebase::to_base(&storage.pool, sui_amount, false);

    // mint_isui_logic will update the pool
    let sft_yield = sui_yield::new( 
      sui_yield_storage,
      (maturity as u256),
      sui_amount,
      shares_amount,
      ctx
    );

    let sft_principal = sui_principal::new(sui_principal_storage, (maturity as u256), sui_amount, ctx);

    emit(MintStrippedBond { 
      sender: tx_context::sender(ctx), 
      sui_amount, 
      sui_principal_id: object::id(&sft_principal),
      sui_yield_id: object::id(&sft_yield),
      validator: validator_address 
    });

    (
      sft_principal,
      sft_yield
    ) 
  } 

  // @dev This function allows the caller to call the stripped bond. It rquires both components to turn in to a bond
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to mint.
  * @param sui_yield_storage The shared object of Sui Yield, it contains the treasury_cap. We need it to mint.
  * @param sft_principal The residue portion of the bond
  * @param sft_yield The yield portion of the bond
  * @param maturity Back up maturity in case we missed an pool update call (should not happen)
  * @param validator_address A validator to stake any leftover
  * @return Coin<SUI> in exchange for the Sui Principal burned
  */
  public fun call_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    sft_principal: SemiFungibleToken<SUI_PRINCIPAL>,
    sft_yield: SuiYield,
    maturity: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    let slot = (sui_yield::slot(&sft_yield) as u64);
    
    // They must be with the same slot
    assert!((slot as u256) == sui_principal::slot(&sft_principal), EMistmatchedSlots);
    // They must have the same value
    assert!(sui_yield::value(&sft_yield) == sui_principal::value(&sft_principal), EMistmatchedValues);

    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);

    // Destroy both tokens
    // Calculate how much Sui they are worth
    let sui_value_to_return = get_pending_yield_logic(storage, &sft_yield, maturity, ctx) + sui_principal::burn_destroy(sui_principal_storage, sft_principal);
    sui_yield::burn_destroy(sui_yield_storage, sft_yield);

    emit(CallBond { 
      sui_amount: 
      sui_value_to_return, 
      sender: tx_context::sender(ctx), 
      maturity: slot,
    });
    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_value_to_return, false);

    // Unstake Sui
    remove_staked_sui(wrapper, storage, sui_value_to_return, validator_address, ctx)
  }

  // @dev This function burns Sui Principal in exchange for SUI at 1:1 rate
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to burn Sui Principal
  * @param token The Sui Principal, the sender wishes to burn
  * @param validator_address The validator to re stake any remaining Sui if any
  * @return Coin<SUI> in exchange for the Sui Principal burned
  */
  public fun burn_sui_principal(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    token: SemiFungibleToken<SUI_PRINCIPAL>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    assert!(tx_context::epoch(ctx) > (sui_principal::slot(&token) as u64), ETooEarly);

    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);

    // 1 Sui Principal is always 1 SUI
    // Burn the Sui Principal
    let sui_value_to_return = sui_principal::burn_destroy(sui_principal_storage, token);

    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_value_to_return, false);

    emit(BurnSuiPrincipal { sui_amount: sui_value_to_return, sender: tx_context::sender(ctx) });

    // Unstake Sui
    remove_staked_sui(wrapper, storage, sui_value_to_return, validator_address, ctx)
  }

  // @dev This function allows a sender to claim his accrued yield
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param sft_yield The SuiYield to burn in exchange for rewards
  * @param validator_address The validator to re stake any remaining Sui if any
  * @param maturity The back up maturity in case we missed a {update_pool} call
  * @return (SuiYield, Coin<SUI>) Returns the original token and the yield to the sender
  */
  public fun claim_yield(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sft_yield: SuiYield,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ): (SuiYield, Coin<SUI>) {
    
    // Destroy both tokens
    // Calculate how much Sui they are worth
    let sui_amount = get_pending_yield(wrapper, storage, &sft_yield, maturity, ctx);

    // Consider yield paid
    sui_yield::add_rewards_paid(&mut sft_yield, sui_amount);

    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_amount, false);

    emit(ClaimYield { sui_yield_id: object::id(&sft_yield), sui_amount, sender: tx_context::sender(ctx) });

    // Unstake Sui
    (sft_yield, remove_staked_sui(wrapper, storage, sui_amount, validator_address, ctx))
  }

  // ** Functions to handle Whitelist validators

  // Checks if a validator is whitelisted (pays no fee)
  /*
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator The address of the validator
  * @return bool true if it is whitelisted
  */
  public fun is_whitelisted(storage: &PoolStorage, validator: address): bool {
    vector::contains(&storage.whitelist_validators, &validator)
  }

  // Checks if a validator is whitelisted (pays no fee)
  /*
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator The address of the validator
  * @return bool true if it is whitelisted
  */
  public fun borrow_whitelist(storage: &PoolStorage): &vector<address> {
    &storage.whitelist_validators
  }

  // Checks if a validator is whitelisted (pays no fee)
  /*
  * @param storage The Pool Storage Shared Object (this module)
  * @param validator The address of the validator
  * @return bool true if it is whitelisted
  */
  public(friend) fun borrow_mut_whitelist(storage: &mut PoolStorage): &mut vector<address> {
    &mut storage.whitelist_validators
  }

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
  * @param token The Sui Coin, the sender wishes to stake
  * @param validator_address The Sui Coin will be staked in this validator
  * @return Coin<ISUI> in exchange for the Sui deposited
  */
  fun mint_isui_logic(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    token: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,    
  ): u64 {
    // Save the value of Sui being staked in memory
    let stake_value = coin::value(&token);

    // Will save gas since the sui_system will throw
    assert!(stake_value >= MIN_STAKING_THRESHOLD, EInvalidStakeAmount);
    
    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);
  
    // Stake Sui 
    // We need to stake Sui before registering the validator to have access to the pool_id
    let staked_sui = sui_system::request_add_stake_non_entry(wrapper, token, validator_address, ctx);

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
  

  // @dev This function safely unstakes Sui
  /*
  * @param wrapper The Sui System Shared Object
  * @param storage The Pool Storage Shared Object (this module)
  * @param amount The amount of Sui to unstake
  * @param validator_address The validator to restake
  * @return (Vector of Staked Sui, total principal of Staked Sui Removed)
  */
  fun remove_staked_sui(
      wrapper: &mut SuiSystemState, 
      storage: &mut PoolStorage,
      amount: u64,
      validator_address: address,
      ctx: &mut TxContext
    ): Coin<SUI> {
    
    // Create Zero Coin<SUI>, which we will join all Sui to return
    let coin_sui_unstaked = coin::zero<SUI>(ctx);

    // Get the first validator in the linked_table
    let next_validator = linked_table::front(&storage.validators_table);

    // While there is a next validator, we keep looping
    while(option::is_some(next_validator)) {
      // Save the validator address in memory
      let validator_address = *option::borrow(next_validator);

      // Borrow Mut the validator data
      let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

      // If the validator has no staked Sui, we move unto the next one
      if (validator_data.total_principal != 0) {
        let next_key = linked_table::front(&validator_data.staked_sui_table);

        while(option::is_some(next_key)) {
          // Save the first key (epoch) on the staked sui table in memory
          let activation_epoch = *option::borrow(next_key);

          // We are only allowed to unstake if the Staked Suis are active
          if (tx_context::epoch(ctx) >= activation_epoch) {
            // Remove the Staked Sui - to make the table shorter for future iterations
            let staked_sui = linked_table::remove(&mut validator_data.staked_sui_table, activation_epoch);

            // Save the principal in Memory
            let value = staking_pool::staked_sui_amount(&staked_sui);

            // Find out how much amount we have left to unstake
            let amount_left = amount - coin::value(&coin_sui_unstaked);

            /*
            * If we can split the Staked Sui to get the amount left. We split and store the remaining amount in the table. This is to avoid unstaking large amounts and lose rewards.
            */
            if (value >= amount_left + MIN_STAKING_THRESHOLD) {
              // Split the Staked Sui -> Unstake -> Join with the Return Coin
              coin::join(&mut coin_sui_unstaked, coin::from_balance(sui_system::request_withdraw_stake_non_entry(wrapper, staking_pool::split(&mut staked_sui, amount_left, ctx), ctx), ctx));

              // Store the left over Staked Sui
              store_staked_sui(validator_data, staked_sui);
              // Update the validator data
              validator_data.total_principal =  validator_data.total_principal - amount_left;
              // We have unstaked enough
              break
            } else {
              // If we cannot split, we simply unstake the whole Staked Sui
              coin::join(&mut coin_sui_unstaked, coin::from_balance(sui_system::request_withdraw_stake_non_entry(wrapper, staked_sui, ctx), ctx));
              // Update the validator data
              validator_data.total_principal =  validator_data.total_principal - value;
            };
          };

          // Insanity check to make sure we d not keep looping for no reason
          if (coin::value(&coin_sui_unstaked) >= amount) break;
          // Move in the next epoch
          next_key = linked_table::next(&validator_data.staked_sui_table, activation_epoch);
        };
      };

      // No point to keep going if we have unstaked enough      
      if (coin::value(&coin_sui_unstaked) >= amount) break;
      // Get the next validator to keep looping
      next_validator = linked_table::next(&storage.validators_table, validator_address);
    };

    // Check how much we unstaked
    let total_value_unstaked = coin::value(&coin_sui_unstaked);

    // Update the total principal
    storage.total_principal = storage.total_principal - total_value_unstaked;

    // If we unstaked more than the desired amount, we need to restake the different
    if (total_value_unstaked > amount) {
      let extra_value = total_value_unstaked - amount;
      // Split the different in a new coin
      let extra_coin_sui = coin::split(&mut coin_sui_unstaked, extra_value, ctx);
      // Save the current dust in storage
      let dust_value = balance::value(&storage.dust);

      // If we have enough dust and extra sui to stake -> we stake and store in the table
      if (coin::value(&extra_coin_sui) + dust_value >= MIN_STAKING_THRESHOLD) {
        // Join Dust and extra coin
        coin::join(&mut extra_coin_sui, coin::take(&mut storage.dust, dust_value, ctx));
        let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);
        // Stake and store
        store_staked_sui(validator_data, sui_system::request_add_stake_non_entry(wrapper, extra_coin_sui, validator_address, ctx));
        validator_data.total_principal = validator_data.total_principal + extra_value;
      } else {
        // If we do not have enough to stake we save in the dust to be staked later on
        coin::put(&mut storage.dust, extra_coin_sui);
      };

      storage.total_principal = storage.total_principal + extra_value;
    };

    // Return the Sui Coin
    coin_sui_unstaked
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
    let fee_amount = calculate_fee(storage, validator_principal, shares);

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
  fun charge_stripped_bond_mint(
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    validator_principal: u64,
    amount: u64,
    ctx: &mut TxContext
    ): u64 {
    
    // Find the fee % based on the validator dominance and fee parameters.  
    let fee_amount = calculate_fee(storage, validator_principal, amount);

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

  // @dev It returns the Sui value of the {sft}. it does not update the pool so careful!
  /*
  * @param storage The Pool Storage Shared Object (this module)
  * @param sft The SuiYield
  * @return u64 the exchange rate
  */
  fun get_pending_yield_logic(
    storage: &mut PoolStorage, 
    sft_yield: &SuiYield,
    maturity: u64,
    ctx: &mut TxContext
  ): u64 {
    let slot = (sui_yield::slot(sft_yield) as u64);

    let (shares, principal, rewards_paid) = sui_yield::read_data(sft_yield);

    let shares_value = if (tx_context::epoch(ctx) > slot) {
      // If the user is getting the yield after maturity
      // We need to find the exchange rate at maturity

      // Check if the table has slot exchange rate
      // If it does not we use the back up maturity value
      let pool = if (linked_table::contains(&storage.pool_history, slot)) { 
        linked_table::borrow(&storage.pool_history, slot)
      } else {
        // Back up maturity needs to be before the slot
        assert!(slot > maturity, EInvalidBackupMaturity);
        linked_table::borrow(&storage.pool_history, maturity)
      };

      rebase::to_elastic(pool, shares, false)
    } else {
      // If it is before maturity - we just read the pool
      rebase::to_elastic(&storage.pool, shares, false)
    };

    let debt = rewards_paid + principal;

    // Remove the principal to find out how many rewards this SFT has accrued
    if (debt >= shares_value) {
      0
    } else {
      shares_value - debt
    }
  }

  // Core fee calculation logic
  /*
  * @storage: The Pool Storage Shared Object (this module)
  * @validator_principal The amount of Sui principal deposited to the validator
  * @amount The amount being minted
  * @return u64 The fee amount
  */
  fun calculate_fee(
    storage: &PoolStorage,
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

 // ** SDK Functions
  
 public fun read_pool_storage(storage: &PoolStorage): (&Rebase, u64, &LinkedTable<address, ValidatorData>, u64, &Fee, &Coin<ISUI>, &LinkedTable<u64, Rebase>) {
    (
      &storage.pool, 
      storage.last_epoch, 
      &storage.validators_table, 
      storage.total_principal, 
      &storage.fee, 
      &storage.dao_coin,
      &storage.pool_history
    ) 
  }

  public fun read_validator_data(data: &ValidatorData): (&LinkedTable<u64, StakedSui>, u64) {
    (
      &data.staked_sui_table,
      data.total_principal
    )
  }

  // ** TEST FUNCTIONS

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }
}
