module interest_lst::sdk {
  use std::option;
  use std::vector;

  use sui::sui::SUI;
  use sui::coin::Coin;
  use sui::linked_table;
  use sui::tx_context::{Self, TxContext};

  use sui_system::staking_pool;
  use sui_system::sui_system::SuiSystemState;
  
  use interest_lst::rebase::Rebase;
  use interest_lst::isui::{ISUI, InterestSuiStorage};
  use interest_lst::fee_utils::{calculate_fee_percentage};
  use interest_lst::sui_yield::{SuiYieldStorage, SuiYield};
  use interest_lst::semi_fungible_token::{SemiFungibleToken};
  use interest_lst::pool::{Self, PoolStorage, BurnValidatorPayload};
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

  struct ValidatorStakePosition has store, drop {
    validator: address,
    total_principal: u64
  }

  public entry fun mint_isui(
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

  public fun burn_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    validator_payload: vector<BurnValidatorPayload>,
    tokens: vector<Coin<ISUI>>,
    token_value: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(pool::burn_isui(
      wrapper,
      storage,
      interest_sui_storage,
      validator_payload,
      handle_coin_vector(tokens, token_value, ctx),
      validator_address,
      ctx
    ), tx_context::sender(ctx));
  }

  public entry fun mint_stripped_bond(
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

  public fun call_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    validator_payload: vector<BurnValidatorPayload>,
    sft_principal_vector: vector<SemiFungibleToken<SUI_PRINCIPAL>>,
    sft_yield_vector: vector<SuiYield>,
    principal_value: u64,
    yield_value: u64,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(
      pool::call_bond(
        wrapper,
        storage,
        sui_principal_storage,
        sui_yield_storage,
        validator_payload,
        handle_principal_vector(sft_principal_vector, principal_value, ctx),
        handle_yield_vector(sft_yield_vector, yield_value, ctx),
        validator_address,
        maturity,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

  public fun burn_sui_principal(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    validator_payload: vector<BurnValidatorPayload>,
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
        validator_payload,
        handle_principal_vector(sft_principal_vector, principal_value, ctx),
        validator_address,
        ctx
      ),
      tx_context::sender(ctx))
  }

  public fun claim_yield(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    validator_payload: vector<BurnValidatorPayload>,
    sft_yield_vector: vector<SuiYield>,
    yield_value: u64,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ) {
    let (yield, coin_sui) = pool::claim_yield(
      wrapper,
      storage,
      validator_payload,
      handle_yield_vector(sft_yield_vector, yield_value, ctx),
      validator_address,
      maturity,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_yield(yield, sender);
    public_transfer_coin(coin_sui, sender);
  }

  public fun create_burn_validator_payload(
    storage: &PoolStorage,
    amount: u64
  ): vector<BurnValidatorPayload> {
     let (_, _, validators_table, _, _, _, _) = pool::read_pool_storage(storage);

    let total_value = 0;
    let amount = amount + MIN_STAKING_THRESHOLD;
    let data = vector::empty();

    // Get the first validator in the linked_table
    let next_validator = linked_table::front(validators_table);

        // We iterate through all validators. This can grow to 1000+
    while (option::is_some(next_validator)) {
      // Save the validator address in memory. We first check that it exists above.
      let validator_address = *option::borrow(next_validator);

       let (staked_sui_table, total_principal) = pool::read_validator_data(linked_table::borrow(validators_table, validator_address));

      // If the validator does not have any sui staked, we to the next validator
      if (total_principal != 0) {
        let next_key = linked_table::front(staked_sui_table);

        while (option::is_some(next_key)) {
          let activation_epoch = *option::borrow(next_key);
          
          let staked_sui = linked_table::borrow(staked_sui_table, activation_epoch);
          
          let value = staking_pool::staked_sui_amount(staked_sui);

          // We add the different and break;
          if (value > total_value) {
            vector::push_back(&mut data, pool::create_burn_validator_payload(validator_address, activation_epoch, total_value - value));
            total_value = total_value + (total_value - value);
            break
          } else {
            total_value = total_value + value;
            vector::push_back(&mut data, pool::create_burn_validator_payload(validator_address, activation_epoch, value));
          };


          if (total_value >= amount) break;

          next_key = linked_table::next(staked_sui_table, activation_epoch);
        };

      };

      if (total_value >= amount) break;
      
      // Point the next_validator to the next one
      next_validator = linked_table::next(validators_table, validator_address);
    };

    data
  }

  // @dev It allows the frontend to find the current fee of a specific validator
  /*
  * @param pool_storage The shared object of the interest_lst::pool module
  * @param The address of a validator
  * @return The fee in 1e18
  */
  public fun get_validator_fee(storage: &PoolStorage, validator_address: address): u256 {
    let whitelist = pool::borrow_whitelist(storage);

    if (vector::contains(whitelist, &validator_address)) return 0;
    
    let (_, _, validator_table, total_principal, fee, _, _) = pool::read_pool_storage(storage);
    let (_, validator_principal) = pool::read_validator_data(linked_table::borrow(validator_table, validator_address));

    calculate_fee_percentage(fee, (validator_principal as u256), (total_principal as u256))
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

    let validator_data = linked_table::borrow(validators_table, from);

    let (_, total_principal) = pool::read_validator_data(validator_data);

    vector::push_back(&mut data, ValidatorStakePosition { validator: from, total_principal });


      // Get the first validator in the linked_table
    let next_validator = linked_table::next(validators_table, from);
    
    while (option::is_some(next_validator)) {
      let validator_address = *option::borrow(next_validator);

      let validator_data = linked_table::borrow(validators_table, validator_address);

      let (_, total_principal) = pool::read_validator_data(validator_data);

      vector::push_back(&mut data, ValidatorStakePosition { validator: validator_address, total_principal });

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
  public fun get_pool_history(storage: &PoolStorage, total: u64): vector<Rebase> {
    let data = vector::empty();

   let (_, _, _, _, _, _, pool_history) = pool::read_pool_storage(storage);

   let last = linked_table::back(pool_history);
   let index = 0;

    while(option::is_some(last)) {
      if (index > total) break;
      let key = *option::borrow(last);

      vector::push_back(&mut data, *linked_table::borrow(pool_history, key));


      last = linked_table::prev(pool_history, key);
      index = index + 1;
    };

    data
  }
}