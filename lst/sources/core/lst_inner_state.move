module interest_lst::interest_lst_inner_state { 
  use std::option;
  use std::vector;

  use sui::table;
  use sui::sui::SUI;
  use sui::object::ID;
  use sui::balance::{Self, Balance};
  use sui::coin::{Self, Coin, TreasuryCap};
  use sui::versioned::{Self, Versioned};
  use sui::tx_context::{Self, TxContext};
  use sui::linked_table::{Self, LinkedTable};

  use suitears::fund::{Self, Fund};
  use suitears::fixed_point_wad::{wad_mul_up as fmul, wad_div_up as fdiv};
  use suitears::semi_fungible_token::{Self as sft, SftTreasuryCap, SemiFungibleToken};

  use sui_system::sui_system::{Self, SuiSystemState};
  use sui_system::staking_pool::{Self, StakedSui};

  use yield::yield::{Self, YieldCap, Yield};
  
  use interest_lst::errors;
  use interest_lst::events;
  use interest_lst::constants;
  use interest_lst::isui::ISUI;
  use interest_lst::isui_yield::ISUI_YIELD;
  use interest_lst::validator::{Self, Validator};
  use interest_lst::isui_principal::ISUI_PRINCIPAL;
  use interest_lst::unstake_utils::{Self, UnstakePayload};
  use interest_lst::fee_utils::{new as new_fee, calculate_fee_percentage, Fee};
  use interest_lst::staking_pool_utils::{calc_staking_pool_rewards, get_most_recent_exchange_rate};


  friend interest_lst::interest_lst;

  const STATE_VERSION_V1: u64 = 1;

  struct StateV1 has store {
    pool: Fund, // This struct holds the total shares of ISUI and the total SUI (Principal + Rewards). Rebase {base: ISUI total supply, elastic: total Sui}
    last_epoch: u64, // Last epoch that pool was updated
    validators_table: LinkedTable<address, Validator>, // We need a linked table to iterate through all validators once every epoch to ensure all pool data is accurate
    total_principal: u64, // Total amount of StakedSui principal deposited in Interest lst Package
    fee: Fee, // Holds the data to calculate the stake fee
    whitelist_validators: vector<address>,
    pool_history: LinkedTable<u64, Fund>, // Epoch => Pool Data
    dust: Balance<SUI>, // If there is less than 1 Sui from unstaking (rewards)
    dao_balance: Balance<ISUI>, // Fees collected by the protocol in ISUI
    rate: u64, // Weighted APY Arithmetic mean
    total_activate_staked_sui: u64,
    isui_cap: TreasuryCap<ISUI>,
    principal_cap: SftTreasuryCap<ISUI_PRINCIPAL>,
    yield_cap: YieldCap<ISUI_YIELD>
  }

  struct State has store {
    inner: Versioned
  }

  public(friend) fun create_genesis_state(
    isui_cap: TreasuryCap<ISUI>,
    principal_cap: SftTreasuryCap<ISUI_PRINCIPAL>,
    yield_cap: YieldCap<ISUI_YIELD>,
    ctx: &mut TxContext
  ): State {
   let state_v1 = StateV1 {
      pool: fund::empty(),
      last_epoch: 0,
      validators_table: linked_table::new(ctx),
      total_principal: 0,
      fee: new_fee(),
      whitelist_validators: vector[],
      pool_history: linked_table::new(ctx),
      dust: balance::zero(),
      dao_balance: balance::zero(),
      rate: 0,
      total_activate_staked_sui: 0,
      isui_cap,
      principal_cap,
      yield_cap
    };

    State {
      inner: versioned::create(STATE_VERSION_V1, state_v1, ctx)
    }
  }

  // ** Core Functions

  public(friend) fun get_pending_yield(
    sui_state: &mut SuiSystemState,
    state: &mut State,  
    coupon: &Yield<ISUI_YIELD>,
    maturity: u64,
    ctx: &mut TxContext  
  ): u64 {
    let state = load_state_mut(state);
    update_fund_logic(sui_state, state, tx_context::epoch(ctx));
    get_pending_yield_logic(state, coupon, maturity, ctx)
  }

  public(friend) fun update_fund(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    ctx: &mut TxContext,
  ) {
    let epoch = tx_context::epoch(ctx);
    let state = load_state_mut(state);

    update_fund_logic(sui_state, state, epoch);
  }

  public(friend) fun mint_isui(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    asset: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<ISUI> {
    let sui_amount = coin::value(&asset);

    let state = load_state_mut(state);

    let shares = mint_isui_logic(sui_state, state, asset, validator_address, ctx);

    let isui_amount = if (is_whitelisted_logic(state, validator_address)) {
      shares
    } else {
      let validator_principal = validator::total_principal(linked_table::borrow_mut(&mut state.validators_table, validator_address));
      charge_isui_mint(
        state, 
        validator_principal, 
        shares, 
        ctx
      )
    };

    events::emit_mint_isui(tx_context::sender(ctx), sui_amount, isui_amount, validator_address);

    coin::mint(&mut state.isui_cap, isui_amount, ctx)
  }

  public(friend) fun burn_isui(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    asset: Coin<ISUI>,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,    
  ): Coin<SUI> {
    let state = load_state_mut(state);

    update_fund_logic(sui_state, state, tx_context::epoch(ctx));

    let isui_amount = coin::burn(&mut state.isui_cap, asset);

    let sui_amount = fund::sub_shares(&mut state.pool, isui_amount, false);

    events::emit_burn_isui(tx_context::sender(ctx), sui_amount, isui_amount);

    remove_staked_sui(sui_state, state, sui_amount, validator_address, unstake_payload, ctx)
  }

  public(friend) fun mint_stripped_bond(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    asset: Coin<SUI>,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext    
  ): (SemiFungibleToken<ISUI_PRINCIPAL>, Yield<ISUI_YIELD>) {
    assert!(maturity >= tx_context::epoch(ctx), errors::pool_outdated_maturity());

    let sui_amount = coin::value(&asset);
    let state = load_state_mut(state);

    mint_isui_logic(sui_state, state, asset, validator_address, ctx);

    let sui_amount = if (is_whitelisted_logic(state, validator_address)) 
      sui_amount
    else {
      let validator = linked_table::borrow_mut(&mut state.validators_table, validator_address);
      let validator_principal = validator::total_principal(validator);
      charge_stripped_bond_mint(
        state,
        validator_principal,
        sui_amount,
        ctx
      )
    };

    let shares_amount = fund::to_shares(&state.pool, sui_amount, false);

    let coupon = yield::mint(
      &mut state.yield_cap,
      (maturity as u256),
      sui_amount,
      shares_amount,
      ctx
    );

    let principal = sft::mint(&mut state.principal_cap, (maturity as u256), sui_amount, ctx);

    events::emit_mint_stripped_bond(tx_context::sender(ctx), sui_amount, shares_amount, validator_address);

    (principal, coupon)
  }

  public(friend) fun call_bond(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    principal: SemiFungibleToken<ISUI_PRINCIPAL>,
    coupon: Yield<ISUI_YIELD>,
    maturity: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,    
  ): Coin<SUI> {
    let slot = (yield::slot(&coupon) as u64);

    assert!((slot as u256) == sft::slot(&principal), errors::pool_mismatched_maturity());
    assert!(yield::value(&coupon) == sft::value(&principal), errors::pool_mismatched_values());

    let state = load_state_mut(state);

    update_fund_logic(sui_state, state, tx_context::epoch(ctx));

    let burn_amount = sft::burn(&mut state.principal_cap, principal);
    let sui_amount = get_pending_yield_logic(state, &coupon, maturity, ctx) + burn_amount;
    yield::burn(&mut state.yield_cap, coupon);

    events::emit_call_bond(tx_context::sender(ctx), sui_amount, maturity);

    fund::sub_underlying(&mut state.pool, sui_amount, false);

    remove_staked_sui(sui_state, state, sui_amount, validator_address, unstake_payload, ctx)
  }

  public(friend) fun burn_sui_principal(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    principal: SemiFungibleToken<ISUI_PRINCIPAL>,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    assert!(tx_context::epoch(ctx) >= (sft::slot(&principal) as u64), errors::pool_bond_not_matured());

    let state = load_state_mut(state);

    update_fund_logic(sui_state, state, tx_context::epoch(ctx));

    let sui_amount = sft::burn(&mut state.principal_cap, principal);

    fund::sub_underlying(&mut state.pool, sui_amount, false);

    events::emit_burn_sui_principal(tx_context::sender(ctx), sui_amount);

    remove_staked_sui(sui_state, state, sui_amount, validator_address, unstake_payload, ctx)
  }

  public(friend) fun claim_yield(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    coupon: Yield<ISUI_YIELD>,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    maturity: u64,
    ctx: &mut TxContext,
  ): (Yield<ISUI_YIELD>, Coin<SUI>) {
    let state = load_state_mut(state);

    update_fund_logic(sui_state, state, tx_context::epoch(ctx));
    
    let sui_amount = get_pending_yield_logic(state, &coupon, maturity, ctx);

    let is_zero_amount = sui_amount == 0;

    if (!is_zero_amount) {
      // Consider yield paid
      yield::add_rewards_paid(&state.yield_cap, &mut coupon, sui_amount);
      // We need to update the pool
      fund::sub_underlying(&mut state.pool, sui_amount, false);
    };

    events::emit_claim_yield(tx_context::sender(ctx), sui_amount);

    (
      if (tx_context::epoch(ctx) > (yield::slot(&coupon) as u64)) 
          yield::expire(&mut state.yield_cap, coupon, ctx)
        else
          coupon,
      if (is_zero_amount)
        coin::zero(ctx)
      else 
        remove_staked_sui(sui_state, state, sui_amount, validator_address, unstake_payload, ctx)
    )
  }

  // ** Read only Functions

  public(friend) fun read_state(state: &mut State): (&Fund, u64, &LinkedTable<address, Validator>, u64, &Fee, &Balance<ISUI>, &LinkedTable<u64, Fund>) {
    let state = load_state(state);
    (
      &state.pool, 
      state.last_epoch,
      &state.validators_table,
      state.total_principal,
      &state.fee,
      &state.dao_balance,
      &state.pool_history
    )
  }

  public(friend) fun read_validator_data(state: &mut State, validator_address: address): (&LinkedTable<u64, StakedSui>, u64) {
    let state = load_state_mut(state);
    let validator = linked_table::borrow_mut(&mut state.validators_table, validator_address);
    let total_principal = validator::total_principal(validator);

    (validator::borrow_staked_sui_table(validator), total_principal)
  }

  public(friend) fun is_whitelisted(state: &mut State, validator_address: address): bool {
    let state = load_state(state);
    is_whitelisted_logic(state, validator_address)
  }

  // ** Private Functions

  fun load_state(self: &mut State): &StateV1 {
    load_state_maybe_upgrade(self)
  }

  fun load_state_mut(self: &mut State): &mut StateV1 {
    load_state_maybe_upgrade(self)
  }

  fun is_whitelisted_logic(state: &StateV1, validator: address): bool {
    vector::contains(&state.whitelist_validators, &validator)
  }

  fun mint_isui_logic(
    sui_state: &mut SuiSystemState,
    state: &mut StateV1,
    asset: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,   
  ): u64 {
    let sui_amount = coin::value(&asset);

    // Will save gas since the sui_system will throw
    assert!(sui_amount >= constants::min_stake_amount(), errors::pool_invalid_stake_amount());

    update_fund_logic(sui_state, state, tx_context::epoch(ctx));

    let staked_sui = sui_system::request_add_stake_non_entry(sui_state, asset, validator_address, ctx);

    add_validator(state, staking_pool::pool_id(&staked_sui), validator_address, ctx);

    let validator = linked_table::borrow_mut(&mut state.validators_table, validator_address);

    store_staked_sui(validator, staked_sui);

    state.total_principal = state.total_principal + sui_amount;

    fund::add_underlying(&mut state.pool, sui_amount, false)
  }

  fun update_fund_logic(
    sui_state: &mut SuiSystemState,
    state: &mut StateV1,
    epoch: u64   
  ) {
    if (epoch == state.last_epoch || fund::shares(&state.pool) == 0) return;

    let total_rewards = 0;
    let total_activate_staked_sui = 0;

    let next_validator = linked_table::front(&state.validators_table);

    while(option::is_some(next_validator)) {
      let validator_address = *option::borrow(next_validator);

      let validator_data = linked_table::borrow_mut(&mut state.validators_table, validator_address);

      let pool_exchange_rates = sui_system::pool_exchange_rates(sui_state, &validator::staking_pool_id(validator_data));
      let current_exchange_rate = get_most_recent_exchange_rate(pool_exchange_rates, epoch);

      if (validator::total_principal(validator_data) != 0) {

        let staked_sui_table = validator::borrow_staked_sui_table(validator_data);

        let next_key = linked_table::front(staked_sui_table);

        while (option::is_some(next_key)) {
          let activation_epoch = *option::borrow(next_key);
          
          let staked_sui = linked_table::borrow(staked_sui_table, activation_epoch);
          
          if (epoch >= activation_epoch) {
            let amount = staking_pool::staked_sui_amount(staked_sui);
            total_rewards = total_rewards + calc_staking_pool_rewards(
              // ** IMPORTANT AUDITORS - Can this throw???
              table::borrow(pool_exchange_rates, activation_epoch),
              current_exchange_rate,
              amount
            );
            total_activate_staked_sui = total_activate_staked_sui + amount;
          };

          next_key = linked_table::next(staked_sui_table, activation_epoch);
        };
      };
      
      // Point the next_validator to the next one
      next_validator = linked_table::next(&state.validators_table, validator_address);
    };

    fund::set_underlying(&mut state.pool, total_rewards + state.total_principal);
    state.last_epoch = epoch;
    state.total_activate_staked_sui = total_activate_staked_sui;

    let num_of_epochs = (linked_table::length(&state.pool_history) as u256);
    let current_rate = (fdiv((total_rewards as u128),(state.total_principal as u128)) as u64);

    state.rate = if (state.rate == 0) 
    { current_rate } 
    else 
    { ((((current_rate as u256) * num_of_epochs) + (state.rate as u256)) / (num_of_epochs + 1) as u64) };

    // We save the epoch => Pool Rebase
    linked_table::push_back(
      &mut state.pool_history, 
      epoch, 
      state.pool
    );

    events::emit_update_fund(state.total_principal, total_rewards);    
  }

  fun add_validator(
    state: &mut StateV1,
    staking_pool_id: ID,
    validator_address: address,
    ctx: &mut TxContext,       
  ) {
    if (linked_table::contains(&state.validators_table, validator_address)) return;   

    linked_table::push_back(&mut state.validators_table, validator_address, validator::create_genesis_state(staking_pool_id, ctx)); 
  }

  fun store_staked_sui(validator: &mut Validator, staked_sui: StakedSui) {
    let activation_epoch = staking_pool::stake_activation_epoch(&staked_sui);

    let staked_sui_table = validator::borrow_mut_staked_sui_table(validator);

      // If we already have Staked Sui with the same validator and activation epoch saved in the table, we will merge them
      if (linked_table::contains(staked_sui_table, activation_epoch)) {
        // Merge the StakedSuis
        staking_pool::join_staked_sui(
          linked_table::borrow_mut(staked_sui_table, activation_epoch), 
          staked_sui
        );
      } else {
        // If there is no StakedSui with the {activation_epoch} on our table, we add it.
        linked_table::push_back(staked_sui_table, activation_epoch, staked_sui);
      };
  }

  fun remove_staked_sui(
    sui_state: &mut SuiSystemState,
    state: &mut StateV1,
    amount: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,  
  ): Coin<SUI> {
    // Create Zero Coin<SUI>, which we will join all Sui to return
    let coin_sui_unstaked = coin::zero<SUI>(ctx);

    let len = vector::length(&unstake_payload);
    let i = 0;

    while (len > i) {
      let (validator_address, epoch_amount_vector) = unstake_utils::read_unstake_payload(vector::borrow(&unstake_payload, i));

      let validator = linked_table::borrow_mut(&mut state.validators_table, validator_address);


      let j = 0;
      let l = vector::length(epoch_amount_vector);
      while (l > j) {
        let epoch_amount = vector::borrow(epoch_amount_vector, j);
        let (activation_epoch, unstake_amount, split) = unstake_utils::read_epoch_amount(epoch_amount);

        let staked_sui_table = validator::borrow_mut_staked_sui_table(validator);

        let staked_sui = linked_table::remove(staked_sui_table, activation_epoch);

        let value = staking_pool::staked_sui_amount(&staked_sui);

        if (split) {
          // Split the Staked Sui -> Unstake -> Join with the Return Coin
          coin::join(&mut coin_sui_unstaked, coin::from_balance(sui_system::request_withdraw_stake_non_entry(sui_state, staking_pool::split(&mut staked_sui, unstake_amount, ctx), ctx), ctx));

          // Store the left over Staked Sui
          store_staked_sui(validator, staked_sui);
          
          // Update the validator data
          let validator_total_principal = validator::borrow_mut_total_principal(validator);
          *validator_total_principal =  *validator_total_principal - unstake_amount;

          // We have unstaked enough          
        } else {
          // If we cannot split, we simply unstake the whole Staked Sui
          coin::join(&mut coin_sui_unstaked, coin::from_balance(sui_system::request_withdraw_stake_non_entry(sui_state, staked_sui, ctx), ctx));
          // Update the validator data
          let validator_total_principal = validator::borrow_mut_total_principal(validator);
          *validator_total_principal =  *validator_total_principal - value;        
        };

        j = j + 1;
      };

      i = i + 1;
    };

    // Check how much we unstaked
    let total_value_unstaked = coin::value(&coin_sui_unstaked);

    // Update the total principal
    state.total_principal = state.total_principal - total_value_unstaked;
    state.total_activate_staked_sui = state.total_activate_staked_sui - total_value_unstaked;

    // If we unstaked more than the desired amount, we need to restake the different
    if (total_value_unstaked > amount) {
      let extra_value = total_value_unstaked - amount;
      // Split the different in a new coin
      let extra_coin_sui = coin::split(&mut coin_sui_unstaked, extra_value, ctx);
      // Save the current dust in storage
      let dust_value = balance::value(&state.dust);

      // If we have enough dust and extra sui to stake -> we stake and store in the table
      if (extra_value + dust_value >= constants::min_stake_amount()) {
        // Join Dust and extra coin
        coin::join(&mut extra_coin_sui, coin::take(&mut state.dust, dust_value, ctx));
        let validator = linked_table::borrow_mut(&mut state.validators_table, validator_address);
        // Stake and store
        store_staked_sui(validator, sui_system::request_add_stake_non_entry(sui_state, extra_coin_sui, validator_address, ctx));
        let validator_total_principal = validator::borrow_mut_total_principal(validator);
        *validator_total_principal =  *validator_total_principal - extra_value;  
      } else {
        // If we do not have enough to stake we save in the dust to be staked later on
        coin::put(&mut state.dust, extra_coin_sui);
      };

      state.total_principal = state.total_principal + extra_value;
    };

    // Return the Sui Coin
    coin_sui_unstaked
  }

  fun get_pending_yield_logic(
    state: &mut StateV1,
    coupon: &Yield<ISUI_YIELD>,
    maturity: u64,
    ctx: &mut TxContext
  ): u64 {
    let slot = (yield::slot(coupon) as u64);

    let (shares, principal, rewards_paid) = yield::read_data(coupon);

    let shares_value = if (tx_context::epoch(ctx) > slot) {
      // If the user is getting the yield after maturity
      // We need to find the exchange rate at maturity

      // Check if the table has slot exchange rate
      // If it does not we use the back up maturity value
      let pool = if (linked_table::contains(&state.pool_history, slot)) { 
        linked_table::borrow(&state.pool_history, slot)
      } else {
        // Back up maturity needs to be before the slot
        assert!(slot > maturity, errors::pool_invalid_backup_maturity());
        linked_table::borrow(&state.pool_history, maturity)
      };

      fund::to_underlying(pool, shares, false)
    } else {
      // If it is before maturity - we just read the pool
      fund::to_underlying(&state.pool, shares, false)
    };

    let debt = rewards_paid + principal;

    // Remove the principal to find out how many rewards this SFT has accrued
    if (debt >= shares_value) {
      0
    } else {
      shares_value - debt
    }
  }

  fun charge_isui_mint(
    state: &mut StateV1,
    validator_principal: u64,
    shares: u64,
    ctx: &mut TxContext
  ): u64 {
    
    // Find the fee % based on the validator dominance and fee parameters.  
    let fee_amount = calculate_fee(state, validator_principal, shares);

    // If the fee is zero, there is nothing else to do
    if (fee_amount == 0) return shares;

    // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
    coin::put(&mut state.dao_balance, coin::mint(&mut state.isui_cap, fee_amount, ctx));
    // Return the shares amount to mint to the sender
    shares - fee_amount
  }

  fun charge_stripped_bond_mint(
    state: &mut StateV1,
    validator_principal: u64,
    amount: u64,
    ctx: &mut TxContext
    ): u64 {
    
    // Find the fee % based on the validator dominance and fee parameters.  
    let fee_amount = calculate_fee(state, validator_principal, amount);

    // If the fee is zero, there is nothing else to do
    if (fee_amount == 0) return amount;

    // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
    coin::put(&mut state.dao_balance, coin::mint(
      &mut state.isui_cap, 
      fund::to_shares(&state.pool, fee_amount, false), 
      ctx
    ));

    // Return the shares amount to mint to the sender
    amount - fee_amount
  }

  fun calculate_fee(
    state: &StateV1,
    validator_principal: u64,
    amount: u64,
  ): u64 {
    // Find the fee % based on the validator dominance and fee parameters.  
    let fee = calculate_fee_percentage(
      &state.fee,
      (validator_principal as u128),
      (state.total_principal as u128)
    );

    // Calculate fee
    (fmul((amount as u128), fee) as u64)
  }

  /// This function should always return the latest supported version.
  /// If the inner version is old, we upgrade it lazily in-place.
  fun load_state_maybe_upgrade(self: &mut State): &mut StateV1 {
    upgrade_to_latest(self);
    versioned::load_value_mut(&mut self.inner)
  }

  fun upgrade_to_latest(self: &mut State) {
    // * IMPORTANT: When new versions are added, we need to explicitly upgrade here.
    assert!(versioned::version(&self.inner) == STATE_VERSION_V1, errors::invalid_version());
  }
}