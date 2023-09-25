module interest_lst::constants {

  public fun one_sui_value(): u64 {
    1_000_000_000
  }

  public fun five_percent(): u64 {
    50_000_000
  }

  public fun u256_max_u128(): u256 {
    340282366920938463463374607431768211455
  }

  public fun u128_max_u128(): u128 {
    340282366920938463463374607431768211455
  }

  public fun ten_years_epochs(): u64 {
    3_650
  }

  public fun initial_r_numerator(): u128 {
    287
  }

  public fun min_amm_lp_token_value(): u64 {
    100
  }

  public fun n_denominator(): u128 {
    3650000
  }

  public fun max_n_numerator(): u128 {
    2000
  }
}