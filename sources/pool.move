// This contract manages the minting/burning of iSUi Coins and staking/unstaking Sui in Validators
// ISUI is a share of the total SUI principal + rewards this module owns
// ISUI_PC is always 1 SUI as it represents the principal owned by this module
// ISUI_YC is a share of the SUI Rewards owned by this module
module interest_lsd::pool {
  use std::ascii::{String}; 
  use std::option::{Self, Option};

  use sui::transfer;
  use sui::sui::{SUI};
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::event::{emit};
  use sui::dynamic_field as field;
  use sui::tx_context::{Self, TxContext};
  use sui::linked_table::{Self, LinkedTable};
  use sui::table;

  use sui_system::sui_system::{Self, SuiSystemState};
  use sui_system::staking_pool::{Self, StakedSui};

  use interest_lsd::admin::{AdminCap};
  use interest_lsd::isui::{Self, ISUI, InterestSuiStorage};
  use interest_lsd::isui_pc::{ISUI_PC};
  use interest_lsd::isui_yc::{ISUI_YC};
  use interest_lsd::rebase::{Self, Rebase};
  use interest_lsd::heap::{Self, Heap};
  use interest_lsd::type_name_utils::{get_type_name_string, get_coin_data_key};
  use interest_lsd::fees_utils::{calculate_fee_percentage};
  use interest_lsd::math::{fmul, scalar};
  use interest_lsd::staking_pool_utils::{calc_staking_pool_rewards};
  
  // ** Constants

  // ** Errors

  const INVALID_FEE: u64 = 0; // All values inside Fees Struct must be equal or below 1e18 as it represents 100%
  const INVALID_STAKE_AMOUNT: u64 = 1; // Users need to stake more than 1 MIST as the sui_system will throw 0 value stakes

  // ** Structs

  // Formula is
  // dominance = validator_principal / total_principal
  // If the dominance >= kink
  // Fee = ((dominance - kink) * jump) + (kink * base)
  // Fee = dominance * base
  struct Fees has store {
    base: u256,
    kink: u256,
    jump: u256
  }
  
  // TODO MIGHT CHANGE THIS AS IT IS ONLY STORING THE DAO PROFITS
  struct CoinData<phantom T> has key, store {
    id: UID, // front end to grab and display data
    dao_coin: Coin<T> // fees accumulatted by the protocol
  }


  struct ValidatorData has key, store {
    id: UID, // front end to grab and display data,
    heap: Heap<StakedSui>, // max heap to find the staked sui when users wish to redeem LSD for Sui + Rewards
    last_staked_sui: Option<StakedSui>, // cache to merge StakedSui with the same metadata to keep the heap compact
    staking_pool_id: Option<ID>, // the ID of the validator StakingPool
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
    fees: Fees // Holds the fee data. Explanation on how the fees work above.
  }

  // ** Events

  // Emitted when the DAO updates the fees
  struct NewFees has copy, drop {
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
    
    // No fees until we have over 10 validators
    let storage = PoolStorage {
      id: object::new(ctx),
      pool: rebase::new(),
      last_epoch: tx_context::epoch(ctx),
      validators_table: linked_table::new(ctx),
      total_principal: 0,
      fees: Fees {
        base: 0,
        kink: 0,
        jump: 0
      }
    };

    // Register the Coin Data for the 3 assets
    // TODO at the moment the CoinData only holds the fees. Might change in the future
    init_coin_data<ISUI>(&mut storage, ctx);
    init_coin_data<ISUI_PC>(&mut storage, ctx);
    init_coin_data<ISUI_YC>(&mut storage, ctx);

    // Share the PoolStorage Object with the Sui network
    transfer::share_object(storage);
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
    // Save current epoch in memory
    let epoch = tx_context::epoch(ctx);

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
          table::borrow(sui_system::pool_exchange_rates(wrapper, option::borrow(&validator_data.staking_pool_id)), epoch),
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

  // ** Interest Sui Functions

  // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
  /*
  * @wrapper The Sui System Shared Object
  * @storage The Pool Storage Shared Object (this module)
  * @interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
  * @stake The Sui Coin, the sender wishes to stake
  * @validator_address The Sui Coin will be staked in this validator
  * @return Coin<ISUI> in exchange for the Sui deposited
  */
  public fun mint_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    stake: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<ISUI> {
    // Save the value of Sui being staked in memory
    let stake_value = coin::value(&stake);

    // Will save gas the sui_system will throw 0 Sui deposits
    assert!(stake_value != 0, INVALID_STAKE_AMOUNT);
    
    // Need to update the entire state of Sui/Sui Rewards once every epoch
    // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
    update_pool(wrapper, storage, ctx);
  
    // Stake the Sui 
    // We need to stake the Sui before registering the validator to have access to the pool_id
    let staked_sui = sui_system::request_add_stake_non_entry(wrapper, stake, validator_address, ctx);

    // Register the validator once in the linked_list
    safe_register_validator(storage, staking_pool::pool_id(&staked_sui), validator_address, ctx);

    // Store the Sui in storage
    // It returns the total sui principal staked in the validator
    // We need to calculate the fee
    let validator_total_principal = store_staked_sui(storage, staked_sui, validator_address);

    // Update the Sui Pool 
    // We round down to give the edge to the protocol
    let shares = rebase::add_elastic(&mut storage.pool, stake_value, false);

    // Charge the admin fee if it is turned on
    // It will mint the ISUI because we want the total supply of ISUI to reflect the shares in the pool to ensure the exchange rate is correct
    // It returns the shares - dao fee
    let shares_to_mint = charge_isui_mint(storage, interest_sui_storage, validator_total_principal, shares, ctx);

    // Mint iSUI to the caller
    isui::mint(interest_sui_storage, shares_to_mint, ctx)
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
  entry public fun update_fees(
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
    storage.fees.base = base;
    storage.fees.kink = kink;
    storage.fees.jump = jump;

    // Emit event
    emit(NewFees { base, kink, jump });
  }

  // @dev This function allows the DAO to withdraw fees.
  /*
  * @_: The AdminCap
  * @storage: The Pool Storage Shared Object (this module)
  * @amount: The value of fees to withdraw
  * @return the fees in Coin<T>
  */
  public fun withdraw_fees<T>(
    _: &AdminCap,
    storage: &mut PoolStorage, 
    amount: u64,
    ctx: &mut TxContext
  ): Coin<T> {
    
    // Emit the event
    emit(DaoWithdraw<T> {amount, sender: tx_context::sender(ctx) });

    // Split the Fees and sent the desired amount
    coin::split(&mut borrow_mut_coin_data<T>(storage).dao_coin, amount, ctx)
  }

  // ** CORE OPERATIONS


  // @dev This function stores the StakedSui in a cache to be merged to all other StakedSui with the same metadata. 
  // It will move the StakedSui to a MAX heap, once a StakedSui with new metadata is stored
  /*
  * @storage: The Pool Storage Shared Object (this module)
  * @staked_sui: The StakedSui Object to store
  * @validator_address: The address of the validator that minted the StakedSui
  * @return The total principal staked in the validator
  */
  fun store_staked_sui(
    storage: &mut PoolStorage,
    staked_sui: StakedSui,
    validator_address: address,
  ): u64 {
    // The principal in the staked sui
    let staked_sui_amount = staking_pool::staked_sui_amount(&staked_sui);

    // Save the validator data in memory
    let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

    // If there is a staked sui in the cache - we wanna merge with the current one or store in the heap
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
        // If they cannot be merged, we want to store the cache in the heap and cache the new one

        // Store the last_staked_sui in the heap
        heap::insert(&mut validator_data.heap, staking_pool::staked_sui_amount(&last_staked_sui), last_staked_sui);
        // Store the new StakedSui in the cache
        option::fill(&mut validator_data.last_staked_sui, staked_sui);
      };

    } else {
      // If there is nothing in the cache, we cache the most recent staked sui
      option::fill(&mut validator_data.last_staked_sui, staked_sui);
    };

    // Update the total principal in this entire module
    storage.total_principal = storage.total_principal + staked_sui_amount;
    // Update the total principal staked in this validator
    validator_data.total_principal = validator_data.total_principal + staked_sui_amount;
    // Return the total principal to the caller
    validator_data.total_principal
  }

  // ** Utility Fns

  // TODO NEED TO SEE IF COIN DATA needs to be saved
  // Adds a dynamic field to the storage to store the CoinData struct 
  /*
  * @storage: The Pool Storage Shared Object (this module)
  */
  fun init_coin_data<T>(storage: &mut PoolStorage, ctx: &mut TxContext) {
    field::add(&mut storage.id, get_coin_data_key(get_type_name_string<T>()), CoinData {
      id: object::new(ctx),
      dao_coin: coin::zero<T>(ctx)
    });
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
      storage.fees.base,
      storage.fees.kink,
      storage.fees.jump,
      (validator_principal as u256),
      (storage.total_principal as u256)
    );

    // If the fee is zero, there is nothing else to do
    if (fee == 0) return shares;

    // Calculate fee
    let fee_amount = (fmul((shares as u256), fee) as u64);
    // Save CoinData in memory
    let coin_data = borrow_mut_coin_data<ISUI>(storage);
    // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
    coin::join(&mut coin_data.dao_coin, isui::mint(interest_sui_storage, fee_amount, ctx));
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
        heap: heap::new(ctx),
        last_staked_sui: option::none(),
        staking_pool_id: option::some(id),
        last_rewards: 0,
        total_principal: 0
      }); 
  }

  // ** Borrow Functions

  // @dev Helper Function to easily load Coin Data.
  /*
  * @storage: The Pool Storage Shared Object (this module)
  * @return Mutable Ref of the CoinData
  */
  fun borrow_mut_coin_data<T>(storage: &mut PoolStorage): &mut CoinData<T> {
    field::borrow_mut<String, CoinData<T>>(&mut storage.id, get_coin_data_key(get_type_name_string<T>()))
  }
  
}