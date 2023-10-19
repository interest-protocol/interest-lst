module interest_lst::interest_lst_inner_state { 
  use std::option;
  use std::vector;

  use sui::table;
  use sui::sui::SUI;
  use sui::object::{Self, UID, ID};
  use sui::balance::{Self, Balance};
  use sui::coin::{Self, Coin, TreasuryCap};
  use sui::versioned::{Self, Versioned};
  use sui::tx_context::{Self, TxContext};
  use sui::linked_table::{Self, LinkedTable};

  use suitears::fund::{Self, Fund};
  use suitears::semi_fungible_token::{Self, SftTreasuryCap};
  use suitears::fixed_point_wad::{wad_mul_up as fmul, wad_div_up as fdiv};

  use sui_system::sui_system::{Self, SuiSystemState};
  use sui_system::staking_pool::{Self, StakedSui};

  use yield::yield::{Self, YieldCap};
  
  use interest_lst::errors;
  use interest_lst::events;
  use interest_lst::constants;
  use interest_lst::isui::ISUI;
  use interest_lst::isui_yield::ISUI_YIELD;
  use interest_lst::validator::{Self, Validator};
  use interest_lst::isui_principal::ISUI_PRINCIPAL;
  use interest_lst::fee_utils::{new as new_fee, calculate_fee_percentage, set_fee, Fee};
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

  public(friend) fun update_fund(
    sui_state: &mut SuiSystemState,
    state: &mut State,
    ctx: &mut TxContext,
  ) {
    let epoch = tx_context::epoch(ctx);
    let state = load_state_maybe_upgrade(state);

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

    let isui_amount = if (is_whitelisted(state, validator_address)) {
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

  fun load_state(self: &mut State): &StateV1 {
    load_state_maybe_upgrade(self)
  }

  fun load_state_mut(self: &mut State): &mut StateV1 {
    load_state_maybe_upgrade(self)
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

  fun is_whitelisted(state: &StateV1, validator: address): bool {
    vector::contains(&state.whitelist_validators, &validator)
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