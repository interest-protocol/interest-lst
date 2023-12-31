// Module finds out the current total rewards an account has accrued with a validator
// Re-engineered the logic from https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-system/sources/staking_pool.move
module interest_lst::staking_pool_utils {

  use sui_system::staking_pool::{Self, PoolTokenExchangeRate};

  use sui::table::{Self, Table};

  use interest_lst::errors;

  fun get_sui_amount(exchange_rate: &PoolTokenExchangeRate, token_amount: u64): u64 {
      // When either amount is 0, that means we have no stakes with this pool.
      // The other amount might be non-zero when there's dust left in the pool.

      let (exchange_sui_amount, exchange_pool_token_amount) = (
          staking_pool::sui_amount(exchange_rate),
          staking_pool::pool_token_amount(exchange_rate)
        );

      if (exchange_sui_amount == 0 || exchange_pool_token_amount == 0) {
            return token_amount
      };
      let res = (exchange_sui_amount as u128)
              * (token_amount as u128)
              / (exchange_pool_token_amount as u128);
      (res as u64)
  }

  fun get_token_amount(exchange_rate: &PoolTokenExchangeRate, sui_amount: u64): u64 {
    // When either amount is 0, that means we have no stakes with this pool.
    // The other amount might be non-zero when there's dust left in the pool.

    let (exchange_sui_amount, exchange_pool_token_amount) = (
          staking_pool::sui_amount(exchange_rate),
          staking_pool::pool_token_amount(exchange_rate)
        );

    if (exchange_sui_amount == 0 || exchange_pool_token_amount == 0) {
      return sui_amount
    };
      let res = (exchange_pool_token_amount as u128)
              * (sui_amount as u128)
              / (exchange_sui_amount as u128);
      (res as u64)
    }

  public fun get_most_recent_exchange_rate(rates: &Table<u64, PoolTokenExchangeRate>, current_epoch: u64): &PoolTokenExchangeRate {
    if (table::contains(rates, current_epoch)) return table::borrow(rates, current_epoch);

    let i = current_epoch - 1;
    while (i > 0) {
      if (table::contains(rates, i)) return table::borrow(rates, i);
      i = i - 1;
    };

    // This should never happen?!
    // A validator with an empty PoolTokenExchangeRate Table
    abort errors::no_exchange_rate_found()
  }  

  public fun calc_staking_pool_rewards(
    activation_exchange_rate: &PoolTokenExchangeRate, 
    current_exchange_rate: &PoolTokenExchangeRate, 
    amount: u64
    ): u64 {

    let pool_token_withdraw_amount = get_token_amount(activation_exchange_rate, amount);

    let total_sui_withdraw_amount = get_sui_amount(current_exchange_rate, pool_token_withdraw_amount);

    if (total_sui_withdraw_amount >= amount)
      total_sui_withdraw_amount - amount
    else 0
  }
}