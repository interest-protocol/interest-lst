// This contract manages the minting/burning of iSUi Coins and staking/unstaking Sui in Validators
// ISUI is a share of the total SUI principal + rewards this module owns
// ISUI_PC is always 1 SUI as it represents the principal owned by this module
// ISUI_YC is a share of the SUI Rewards owned by this module
module interest_lsd::pool { 
  use std::option::{Self, Option};
  use std::vector;

  use sui::transfer;
  use sui::sui::{SUI};
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::event::{emit};
  use sui::tx_context::{Self, TxContext};
  use sui::object_table::{Self, ObjectTable};
  use sui::linked_table::{Self, LinkedTable};
  use sui::table;

  use sui_system::sui_system::{Self, SuiSystemState};
  use sui_system::staking_pool::{Self, StakedSui};

  use interest_lsd::admin::{AdminCap};
  use interest_lsd::isui::{Self, ISUI, InterestSuiStorage};
  use interest_lsd::isui_pc::{Self, ISUI_PC, InterestSuiPCStorage};
  use interest_lsd::isui_yc::{Self, ISUI_YC, InterestSuiYCStorage};
  use interest_lsd::rebase::{Self, Rebase};
  use interest_lsd::fee_utils::{new as new_fee, calculate_fee_percentage, set_fee, Fee};
  use interest_lsd::math::{fmul, scalar};
  use interest_lsd::staking_pool_utils::{calc_staking_pool_rewards};
  
  // ** Constants

  /// StakedSui objects cannot be split to below this amount.
  const MIN_STAKING_THRESHOLD: u64 = 1_000_000_000; // 1 SUI

  // ** Errors

  const INVALID_FEE: u64 = 0; // All values inside Fees Struct must be equal or below 1e18 as it represents 100%
  const INVALID_STAKE_AMOUNT: u64 = 1; // Users need to stake more than 1 MIST as the sui_system will throw 0 value stakes
  const INVALID_UNSTAKE_AMOUNT: u64 = 2; // The sender tried to unstake more than he is allowed 
  const INVALID_INPUT_AMOUNT: u64 = 3;

  // ** Structs

  // This struct compacts the data sent to burn_isui
  // We will remove the {principal} amount of StakedSui from the {validator_address} stored at staked_sui_table with the key {epoch}
  struct BurnISuiValidatorPayload has drop, store {
    epoch: u64,
    validator_address: address,
    principal: u64
  }

  struct ValidatorData has key, store {
    id: UID, // front end to grab and display data,
    staked_sui_table: ObjectTable<u64, StakedSui>, // epoch => StakedSui
    last_staked_sui: Option<StakedSui>, // cache to merge StakedSui with the same metadata to keep the table compact
    staking_pool_id: ID, // the ID of the validator StakingPool
    last_rewards: u64, // The last total rewards fetched
    total_principal: u64 // The total amount of Sui deposited in this validator without the accrueing rewards
  }

  // Shared Object
  // Unfortunately, we cannot make fully exploit Sui concurrency model because we need our LSD Coins to reflect the rewards accrued
  // This allows for users to instantly buy and "Stake Sui" by buying this coin without having to go through all the process
  // This also makes Coins omnichain and a user in Ethereum can buy the coin and he instantly became a Sui Staker
  struct PoolStorage has key {
    id: UID,
    pool: Rebase, // This struct holds current total shares of ISUI and total SUI (Principal + Rewards) is represents. Rebase {base: ISUI total supply, elastic: total Sui}
    last_epoch: u64, // Last epoch that pool was updated
    validators_table: LinkedTable<address, ValidatorData>, // We need a linked table to iterate through all validators once every epoch to ensure all pool data is accurate
    total_principal: u64, // Total amount of principal deposited in Interest LSD Package
    fee: Fee, // Holds the fee data. Explanation on how the fees work above.
    dao_coin: Coin<ISUI> // Fees collected by the protocol in ISUI,
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

  struct MintISuiDerivatives has copy, drop {
    sender: address,
    sui_amount: u64,
    isui_pc_amount: u64,
    isui_yc_amount: u64,
    validator: address
  }

  struct BurnISuiPC has copy, drop {
    sender: address,
    sui_amount: u64,
    isui_pc_amount: u64,    
  }

  struct BurnISuiYC has copy, drop {
    sender: address,
    sui_amount: u64,
    isui_yc_amount: u64,    
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

  fun init(ctx: &mut TxContext) {
    // Share the PoolStorage Object with the Sui network
    transfer::share_object(
        PoolStorage {
        id: object::new(ctx),
        pool: rebase::new(),
        last_epoch: tx_context::epoch(ctx),
        validators_table: linked_table::new(ctx),
        total_principal: 0,
        fee: new_fee(),
        dao_coin: coin::zero<ISUI>(ctx)
      }
    );
  }

  // @dev It returns the exchange rate from ISUI to SUI
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @isui_amount The amount of ISUI
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
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @sui_amount The amount of SUI
  * @return the exchange rate
  */
  public fun get_exchange_rate_sui_to_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage, 
    sui_amount: u64,
    ctx: &mut TxContext
  ): u64 {
    update_pool(wrapper, storage, ctx);
    rebase::to_base(&storage.pool, sui_amount, true)
  }

  // @dev It returns the exchange rate from ISUI_YC to SUI
  /*
  * @storage The Pool Storage Shared Object (this module)
  * @isui_yc_amount The amount of ISUI_YC
  * @return the exchange rate
  */
  public fun get_exchange_rate_isui_yc_to_sui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage, 
    isui_yc_amount: u64,
    ctx: &mut TxContext
  ): u64 {
    // It does not make to quote more ISUI that it exists
    // It will break the calculation assumptions
    assert!(rebase::base(&storage.pool) >= isui_yc_amount, INVALID_INPUT_AMOUNT);
    // We update the pool to make sure the rewards are up to date
    // Then find the total amount of Sui the {isui_yc_amount} would be entitled to if it was iSui as it follows the same minting logic
    // Then we remove the principal component from it
    update_pool(wrapper, storage, ctx);
    let principal_reward = rebase::to_elastic(&storage.pool, isui_yc_amount, false);
    let principal = ((isui_yc_amount as u256) * (storage.total_principal as u256) / (rebase::base(&storage.pool) as u256) as u64);
    principal_reward - principal
  }

  // @dev It returns the exchange rate from SUI to ISUI_YC
  /*
  * @storage The Pool Storage Shared Object (this module)
  * @sui_amount The amount of Sui
  * @return the exchange rate
  */
  public fun get_exchange_rate_sui_to_isui_yc(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage, 
    sui_amount: u64,
    ctx: &mut TxContext
  ): u64 {
    // We find the amount of ISUI in Sui (exchange rate)
    // Then we multiply the desired Sui amount to the exchange rate
    let value = rebase::base(&storage.pool) / 10;
    let exchange_rate = get_exchange_rate_isui_yc_to_sui(wrapper, storage, value, ctx);
    (((sui_amount as u256) * (value as u256) / (exchange_rate as u256)) as u64)
  }

  // @dev This function costs a lot of gas and must be called before any interaction with Interest LSD, because it updates the pool. The pool is needed to ensure all 3 Coins exchange rate is accurate.
  // Anyone can call this function
  // It will ONLY RUN ONCE per epoch
  // Dev Team will call as soon as a new epoch stars so the first user does not need to incur this cost
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
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

    // if the function has been called this epoch, we do not need to do anything else
    // If there are no shares in the pool, it means there is no sui being staked. So there is no updates
    if (epoch == storage.last_epoch || rebase::base(&storage.pool) == 0) return;

    // Get the first validator in the linked_table
    let next_validator = linked_table::front(&storage.validators_table);

    // We iterate through all validators. This can grow to 1000+
    while (option::is_some(next_validator)) {
      // Save the validator address in memory. We first check that it exists above.
      let validator_address = *option::borrow(next_validator);
      // Get the validator data
      let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

      // If the validator does not have any sui staked, we to the next validator
      if (validator_data.total_principal != 0) {
        // We calculate the total rewards we will get based on our current principal staked in the validator
        let total_rewards = calc_staking_pool_rewards(
          table::borrow(sui_system::pool_exchange_rates(wrapper, &validator_data.staking_pool_id), epoch),
          validator_data.total_principal
        );

        // We add the new rewards accrued to the pool. 
        // The new rewards = total_rewards_now - total_rewards_previous_epoch
        // We round down to remain conversative
        rebase::add_elastic(&mut storage.pool, total_rewards - validator_data.last_rewards, false);

        // Update the last_rewards
        validator_data.last_rewards = total_rewards;
      };
      
      // Point the next_validator to the next one
      next_validator = linked_table::next(&storage.validators_table, validator_address);
    };

    // Update the last_epoch
    storage.last_epoch = epoch;
  }

  // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
  * @asset The Sui Coin, the sender wishes to stake
  * @validator_address The Sui Coin will be staked in this validator
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
    
    let shares_to_mint = mint_isui_logic(wrapper, storage, interest_sui_storage, asset, validator_address, ctx);

    emit(MintISui { validator: validator_address, sender: tx_context::sender(ctx), sui_amount, isui_amount: shares_to_mint });

    // Mint iSUI to the caller
    isui::mint(interest_sui_storage, shares_to_mint, ctx)
  }

  // @dev This function burns ISUI and unstakes Sui 
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
  * @validator_payload A vector containing the information about which StakedSui to unstake
  * @asset The iSui Coin, the sender wishes to burn
  * @validator_address The validator to re stake any remaining Sui if any
  * @return Coin<SUI> in exchange for the iSui burned
  */
  public fun burn_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    validator_payload: vector<BurnISuiValidatorPayload>,
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
    assert!((total_principal_unstaked - MIN_STAKING_THRESHOLD) == sui_value_to_return, INVALID_UNSTAKE_AMOUNT);

    emit(BurnISui { sender: tx_context::sender(ctx), sui_amount: sui_value_to_return, isui_amount });

    // Unstake Sui
    unstake_staked_sui(wrapper, storage, staked_sui_vector, validator_address, sui_value_to_return, ctx)
  }

  // @dev This function stakes Sui in a validator chosen by the sender and returns (ISUI_PC, ISUI_YC). 
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
  * @interest_sui_pc_storage The shared object of ISUI_PC, it contains the treasury_cap. We need it to mint ISUI_PC
  * @interest_sui_yc_storage The shared object of ISUI_YC, it contains the treasury_cap. We need it to mint ISUI_YC
  * @asset The Sui Coin, the sender wishes to stake
  * @validator_address The Sui Coin will be staked in this validator
  * @return (COIN<ISUI_PC>, COIN<ISUI_YC>)
  */
  public fun mint_isui_derivatives(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    interest_sui_pc_storage: &mut InterestSuiPCStorage,
    interest_sui_yc_storage: &mut InterestSuiYCStorage,
    asset: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ):(Coin<ISUI_PC>, Coin<ISUI_YC>) {
    let sui_amount = coin::value(&asset);
    let isui_yc_amount = mint_isui_logic(wrapper, storage, interest_sui_storage, asset, validator_address, ctx);

    emit(MintISuiDerivatives { sender: tx_context::sender(ctx), isui_pc_amount: sui_amount, isui_yc_amount, sui_amount, validator: validator_address });

    (
      isui_pc::mint(interest_sui_pc_storage, sui_amount, ctx),
      isui_yc::mint(interest_sui_yc_storage, isui_yc_amount, ctx)
    ) 
  } 

  // @dev This function burns ISUI_PC in exchange for SUI at 1:1 rate
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @interest_sui_pc_storage The shared object of ISUI_PC, it contains the treasury_cap. We need it to burn ISUI_PC
  * @validator_payload A vector containing the information about which StakedSui to unstake
  * @asset The ISUI_PC Coin, the sender wishes to burn
  * @validator_address The validator to re stake any remaining Sui if any
  * @return Coin<SUI> in exchange for the ISUI_PC burned
  */
  public fun burn_isui_pc(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_pc_storage: &mut InterestSuiPCStorage,
    validator_payload: vector<BurnISuiValidatorPayload>,
    asset: Coin<ISUI_PC>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);

    // 1 ISUI_PC is always 1 SUI
    // Burn the ISUI_PC
    let sui_value_to_return = isui_pc::burn(interest_sui_pc_storage, asset, ctx);

    let (staked_sui_vector, total_principal_unstaked) = remove_staked_sui(storage, validator_payload, ctx);

    // Sender must Unstake a bit above his principal because it is possible that the unstaked left over rewards wont meet the min threshold
    assert!((total_principal_unstaked - MIN_STAKING_THRESHOLD) == sui_value_to_return, INVALID_UNSTAKE_AMOUNT);

    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_value_to_return, false);

    emit(BurnISuiPC { sui_amount: sui_value_to_return, sender: tx_context::sender(ctx), isui_pc_amount: sui_value_to_return });

    // Unstake Sui
    unstake_staked_sui(wrapper, storage, staked_sui_vector, validator_address, sui_value_to_return, ctx)
  }

    // @dev This function burns ISUI_YC in exchange for SUI. ISUI_YC grows as the yield of this pool grows
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @interest_sui_yc_storage The shared object of ISUI_YC, it contains the treasury_cap. We need it to burn ISUI_YC
  * @validator_payload A vector containing the information about which StakedSui to unstake
  * @asset The ISUI_YC Coin, the sender wishes to burn
  * @validator_address The validator to re stake any remaining Sui if any
  * @return Coin<SUI> in exchange for the ISUI_PC burned
  */
  public fun burn_isui_yc(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_yc_storage: &mut InterestSuiYCStorage,
    validator_payload: vector<BurnISuiValidatorPayload>,
    asset: Coin<ISUI_YC>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    
    // Burn the {asset} and figure out how much Sui is worth
    let isui_yc_amount = isui_yc::burn(interest_sui_yc_storage, asset, ctx);
    let sui_amount = get_exchange_rate_isui_yc_to_sui(wrapper, storage, isui_yc_amount, ctx);

    // We need to update the pool
    rebase::sub_elastic(&mut storage.pool, sui_amount, false);

    let (staked_sui_vector, total_principal_unstaked) = remove_staked_sui(storage, validator_payload, ctx);

    // Sender must Unstake a bit above his principal because it is possible that the unstaked left over rewards wont meet the min threshold
    assert!((total_principal_unstaked - MIN_STAKING_THRESHOLD) == sui_amount, INVALID_UNSTAKE_AMOUNT);

    emit(BurnISuiYC { sui_amount, sender: tx_context::sender(ctx), isui_yc_amount });

    // Unstake Sui
    unstake_staked_sui(wrapper, storage, staked_sui_vector, validator_address, sui_amount, ctx)
  }

  // ** Admin Functions

  // @dev This function safely updates the fees. It will throw if you pass values higher than 1e18.  
  /*
  * @_: The AdminCap
  * @storage: The Pool Storage Shared Object (this module)
  * @base: The new base
  * @kink: The new kink
  * @jump The new jump
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
    assert!(max >= base && max >= kink && max >= jump, INVALID_FEE);

    // Update the values
    set_fee(&mut storage.fee, base, kink, jump);

    // Emit event
    emit(NewFee { base, kink, jump });
  }

  // @dev This function allows the DAO to withdraw fees.
  /*
  * @_: The AdminCap
  * @storage: The Pool Storage Shared Object (this module)
  * @amount: The value of fees to withdraw
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

    // Split the Fees and sent the desired amount
    coin::split(&mut storage.dao_coin, amount, ctx)
  }

  // ** CORE OPERATIONS

  // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
  * @asset The Sui Coin, the sender wishes to stake
  * @validator_address The Sui Coin will be staked in this validator
  * @return Coin<ISUI> in exchange for the Sui deposited
  */
  fun mint_isui_logic(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    asset: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,    
  ): u64 {
    // Save the value of Sui being staked in memory
    let stake_value = coin::value(&asset);

    // Will save gas since the sui_system will throw
    assert!(stake_value >= MIN_STAKING_THRESHOLD, INVALID_STAKE_AMOUNT);
    
    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);
  
    // Stake the Sui 
    // We need to stake the Sui before registering the validator to have access to the pool_id
    let staked_sui = sui_system::request_add_stake_non_entry(wrapper, asset, validator_address, ctx);

    // Register the validator once in the linked_list
    safe_register_validator(storage, staking_pool::pool_id(&staked_sui), validator_address, ctx);

    // Save the validator data in memory
    let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

    // Store the Sui in storage
    // It returns the total sui principal staked in the validator
    // We need to calculate the fee
    store_staked_sui(validator_data, staked_sui);

    // Update the total principal in this entire module
    storage.total_principal = storage.total_principal + stake_value;
    // Update the total principal staked in this validator
    validator_data.total_principal = validator_data.total_principal + stake_value;

    // Update the Sui Pool 
    // We round down to give the edge to the protocol
    let shares = rebase::add_elastic(&mut storage.pool, stake_value, false);

    // Charge the admin fee if it is turned on
    // It will mint the ISUI because we want the total supply of ISUI to reflect the shares in the pool to ensure the exchange rate is correct
    // It returns the shares - dao fee
    charge_isui_mint(storage, interest_sui_storage, validator_data.total_principal, shares, ctx)
  }

  // @dev This function stores the StakedSui in a cache to be merged to all other StakedSui with the same metadata. 
  // It will move the StakedSui to a table, once a StakedSui with new metadata is stored
  /*
  * @staked_sui: The StakedSui Object to store
  * @validator_data: The Struct Data for the validator where we will deposit the Sui
  * @current_epoch: The current epoch in Sui
  * @return The total principal staked in the validator
  */
  fun store_staked_sui(validator_data: &mut ValidatorData, staked_sui: StakedSui) {

    // If there is a staked sui in the cache - we wanna merge with the current one or store in the table
    if (option::is_some(&validator_data.last_staked_sui)) {
      // Get the last staked sui out of the object storage
      let last_staked_sui = option::extract(&mut validator_data.last_staked_sui);

      // If last staked sui can be joint with the staked sui, we do merge and cache it.
      if (staking_pool::is_equal_staking_metadata(&last_staked_sui, &staked_sui)) {
        // Merge the StakedSuis
        staking_pool::join_staked_sui(&mut last_staked_sui, staked_sui);
        // Store back in the validator data
        option::fill(&mut validator_data.last_staked_sui, last_staked_sui);
      } else {
        // If they cannot be merged, we want to store the cache in the table and cache the new one

        let activation_epoch = staking_pool::stake_activation_epoch(&last_staked_sui);

        if (object_table::contains(&validator_data.staked_sui_table, activation_epoch)) {
          // If there is already a Staked Sui stored we join them
          staking_pool::join_staked_sui(object_table::borrow_mut(&mut validator_data.staked_sui_table, activation_epoch), last_staked_sui);
        } else {
          // If the slot is empty we simply add the Staked Sui
          // Store the last_staked_sui in the Table
          object_table::add(&mut validator_data.staked_sui_table, staking_pool::stake_activation_epoch(&last_staked_sui), last_staked_sui);
        };

        // Store the new StakedSui in the cache
        option::fill(&mut validator_data.last_staked_sui, staked_sui);
      };

    } else {
      // If there is nothing in the cache, we cache the most recent staked sui
      option::fill(&mut validator_data.last_staked_sui, staked_sui);
    };
  }

  // @dev This function safely removes Staked Sui from our storage

  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @validator_payload A vector containing the information about which StakedSui to unstake
  * @return (Vector of Staked Sui, total principal of Staked Sui Removed)
  */
  fun remove_staked_sui(
      storage: &mut PoolStorage,
      validator_payload: vector<BurnISuiValidatorPayload>, 
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

      // Epoch of zero retrieves from the cache - because it is long passed
      let staked_sui = if (payload.epoch != 0) 
          object_table::remove(&mut validator_data.staked_sui_table, payload.epoch) 
        else 
          option::extract(&mut validator_data.last_staked_sui);

      let staked_sui_amount = staking_pool::staked_sui_amount(&staked_sui);

      // We do not need to split the Sui so we can simply save in the vector
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
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @staked_sui_vector The vector of StakedSui to unstake
  * @validator_address The validator to re stake any remaining Sui if any
  * @sui_value_to_return The desired amount of Sui to unstake
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
    validator_data.total_principal = validator_data.total_principal + left_over_amount;
    storage.total_principal = storage.total_principal + left_over_amount;

    // Stake the Sui and store the Staked Sui in memory
    store_staked_sui(
      validator_data, 
      sui_system::request_add_stake_non_entry(wrapper, total_sui_coin, validator_address, ctx)
    );

    sui_to_return
  }

  //Adds a dynamic field to the storage to store the CoinData struct 
  /*
  * @storage: The Pool Storage Shared Object (this module)
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
    // Explanation on line 42
    let fee = calculate_fee_percentage(
      &storage.fee,
      (validator_principal as u256),
      (storage.total_principal as u256)
    );

    // If the fee is zero, there is nothing else to do
    if (fee == 0) return shares;

    // Calculate fee
    let fee_amount = (fmul((shares as u256), fee) as u64);

    // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
    coin::join(&mut storage.dao_coin, isui::mint(interest_sui_storage, fee_amount, ctx));
    // Return the shares amount to mint to the sender
    shares - fee_amount
  }

  // @dev Adds a Validator to the linked_list
  /*
  * @storage: The Pool Storage Shared Object (this module)
  * @id: The StakingPool ID for this validator
  * @validator_address: The address of the validator
  */
  fun safe_register_validator(
    storage: &mut PoolStorage,
    id: ID,
    validator_address: address,
    ctx: &mut TxContext,    
  ) {
    // If the validator is already registered there is nmothing to do.
    if (linked_table::contains(&storage.validators_table, validator_address)) return;
    
    // Add the ValidatorData to the back of the list
    linked_table::push_back(&mut storage.validators_table, validator_address, ValidatorData {
        id: object::new(ctx),
        staked_sui_table: object_table::new(ctx),
        last_staked_sui: option::none(),
        staking_pool_id: id,
        last_rewards: 0,
        total_principal: 0
      }); 
  }  

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }
}