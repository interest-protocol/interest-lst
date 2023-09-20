module interest_lst::sdk {
  use std::option;
  use std::vector;

  use sui::sui::SUI;
  use sui::coin::Coin;
  use sui::tx_context::{Self, TxContext};
  use sui::linked_table::{Self, LinkedTable};

  use sui_system::staking_pool;
  use sui_system::sui_system::SuiSystemState;
  
  use interest_lst::rebase::Rebase;
  use interest_lst::isui::{ISUI, InterestSuiStorage};
  use interest_lst::fee_utils::{calculate_fee_percentage};
  use interest_lst::sui_yield::{SuiYieldStorage, SuiYield};
  use interest_lst::pool::{Self, PoolStorage, ValidatorData};
  use interest_lst::semi_fungible_token::{SemiFungibleToken};
  use interest_lst::sui_principal::{SuiPrincipalStorage, SUI_PRINCIPAL};
  use interest_lst::asset_utils::{
    handle_coin_vector, 
    handle_yield_vector,
    public_transfer_coin,
    public_transfer_yield,
    handle_principal_vector,
    public_transfer_principal
  };

  const MIN_STAKING_THRESHOLD: u64 = 1_000_000_000; // 1 

  struct StakePosition has store, drop {
    epoch: u64,
    amount: u64
  }

  struct ValidatorStakePosition has store, drop {
    validator: address,
    total_principal: u64,
    stakes: vector<StakePosition>
  }

  struct PoolHistory has store {
    pool: Rebase,
    epoch: u64
  }

  entry fun mint_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    tokens: vector<Coin<SUI>>,
    token_value: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(pool::mint_isui(
      wrapper,
      storage,
      interest_sui_storage,
      handle_coin_vector(tokens, token_value, ctx),
      validator_address,
      ctx
    ), tx_context::sender(ctx));
  }

  entry fun burn_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    tokens: vector<Coin<ISUI>>,
    token_value: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(pool::burn_isui(
      wrapper,
      storage,
      interest_sui_storage,
      handle_coin_vector(tokens, token_value, ctx),
      validator_address,
      ctx
    ), tx_context::sender(ctx));
  }

  entry fun mint_stripped_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    tokens: vector<Coin<SUI>>,
    token_value: u64,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ) {
    let (principal, yield) = pool::mint_stripped_bond(
      wrapper,
      storage,
      interest_sui_storage,
      sui_principal_storage,
      sui_yield_storage,
      handle_coin_vector(tokens, token_value, ctx),
      validator_address,
      maturity,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_principal(principal, sender);
    public_transfer_yield(yield, sender);
  }

  entry fun call_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    sft_principal_vector: vector<SemiFungibleToken<SUI_PRINCIPAL>>,
    sft_yield_vector: vector<SuiYield>,
    principal_value: u64,
    yield_value: u64,
    maturity: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(
      pool::call_bond(
        wrapper,
        storage,
        sui_principal_storage,
        sui_yield_storage,
        handle_principal_vector(sft_principal_vector, principal_value, ctx),
        handle_yield_vector(sft_yield_vector, yield_value, ctx),
        maturity,
        validator_address,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

  entry fun burn_sui_principal(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sft_principal_vector: vector<SemiFungibleToken<SUI_PRINCIPAL>>,
    principal_value: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(
      pool::burn_sui_principal(
        wrapper,
        storage,
        sui_principal_storage,
        handle_principal_vector(sft_principal_vector, principal_value, ctx),
        validator_address,
        ctx
      ),
      tx_context::sender(ctx))
  }

  entry fun claim_yield(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sft_yield_vector: vector<SuiYield>,
    yield_value: u64,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ) {
    let (yield, coin_sui) = pool::claim_yield(
      wrapper,
      storage,
      handle_yield_vector(sft_yield_vector, yield_value, ctx),
      validator_address,
      maturity,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_yield(yield, sender);
    public_transfer_coin(coin_sui, sender);
  }

  // @dev It allows the frontend to find the current fee of a specific validator
  /*
  * @param pool_storage The shared object of the interest_lst::pool module
  * @param validator_address The address of a validator
  * @return The fee in 1e18
  */
  public fun get_validator_fee(storage: &PoolStorage, validator_address: address): u256 {
    if (pool::is_whitelisted(storage, validator_address)) return 0;
    
    let (_, _, validator_table, total_principal, fee, _, _) = pool::read_pool_storage(storage);
    let (_, validator_principal) = pool::read_validator_data(linked_table::borrow(validator_table, validator_address));

    calculate_fee_percentage(fee, (validator_principal as u256), (total_principal as u256))
  }

  // @dev It allows the frontend to find the current fee for all validators
  /*
  * @param pool_storage The shared object of the interest_lst::pool module
  * @param validators A vector with the address of all validators
  * @return The fee in 1e18
  */
  public fun get_validators_fee_vector(storage: &PoolStorage, validators: vector<address>): vector<u256> {
    let len = vector::length(&validators);
    let i = 0;
    let result = vector::empty();

    while(len > i) {
      vector::push_back(&mut result, get_validator_fee(storage, *vector::borrow(&validators, i)));
      i = i + 1;
    };
    
    result
  }

  // @dev It allows the frontend to know how much Sui was staked in each validator in our LST
  // Because the validator list can be infinite and vectors are ideal for < 1000 items. We allow the caller to get a specific range
  /*
  * @param pool_storage The shared object of the interest_lst::pool module
  * @param from The first key to get
  * @param to The last key to get
  * @return vector<ValidatorStakePosition>
  */
  public fun get_validators_stake_position(storage: &PoolStorage, from: address, to: address): vector<ValidatorStakePosition> {
    let data = vector::empty<ValidatorStakePosition>();

    let (_, _, validators_table, _, _, _, _) = pool::read_pool_storage(storage);

    push_stake_position(&mut data, validators_table, from);

    let next_validator = linked_table::next(validators_table, from);
    
    while (option::is_some(next_validator)) {
      let validator_address = *option::borrow(next_validator);

      push_stake_position(&mut data, validators_table, validator_address);

      if (validator_address == to) break;

      next_validator = linked_table::next(validators_table, validator_address);
    };

    data
  }

  // @dev It allows the frontend to gather the past balances of the pool to estimate an yearly reward rate
  /*
  * @param pool_storage The shared object of the interest_lst::pool module
  * @param total The number of records to fetch from the last one
  * @return vector<Rebase> - reverse order
  */
  public fun get_pool_history(storage: &PoolStorage, total: u64): vector<PoolHistory> {
    let data = vector::empty();

    let (_, _, _, _, _, _, pool_history) = pool::read_pool_storage(storage);

    let last = linked_table::back(pool_history);
    let index = 0;

    while(option::is_some(last)) {
      if (index > total) break;
      let key = *option::borrow(last);

      vector::push_back(&mut data, PoolHistory {epoch: key, pool: *linked_table::borrow(pool_history, key) });

      last = linked_table::prev(pool_history, key);
      index = index + 1;
    };

    data
  }

  fun push_stake_position(data: &mut vector<ValidatorStakePosition>, validators_table: &LinkedTable<address, ValidatorData>, validator_address: address) {
    let validator_data = linked_table::borrow(validators_table, validator_address);

    let (staked_sui_table, total_principal) = pool::read_validator_data(validator_data);

    let validator_stake = ValidatorStakePosition { validator: validator_address, total_principal, stakes: vector::empty() };

    if (total_principal != 0) {

      let next_key = linked_table::front(staked_sui_table);

      while (option::is_some(next_key)) {
        let activation_epoch = *option::borrow(next_key);
          
        let staked_sui = linked_table::borrow(staked_sui_table, activation_epoch);
          
        vector::push_back(&mut validator_stake.stakes, 
        StakePosition { epoch: staking_pool::stake_activation_epoch(staked_sui), amount: staking_pool::staked_sui_amount(staked_sui) });

        next_key = linked_table::next(staked_sui_table, activation_epoch);
        };
    };

    vector::push_back(data, validator_stake);
  }

}