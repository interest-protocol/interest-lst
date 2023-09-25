module interest_lst::errors {
  public fun zero_division(): u64 { 0 }

  public fun zero_denominator(): u64 { 1 }

  public fun multiplication_u128_overflow(): u64 { 2 }

  public fun division_u128_overflow(): u64 { 3 }

  public fun negative_result(): u64 { 4 }

  public fun fixed_point64_out_of_range(): u64 { 5 }

  public fun sbt_assets_still_locked(): u64 { 6 }

  public fun sbt_lock_period_too_long(): u64 { 7 }

  public fun sft_invalid_witness(): u64 { 8 }

  public fun sft_token_not_empty(): u64 { 9 }

  public fun sft_mismatched_slots(): u64 { 10 }

  public fun zero_address(): u64 { 11 }

  public fun admin_invalid_accept_sender(): u64 { 12 }

  public fun admin_not_accepted(): u64 { 13 }

  // All values inside the Fees Struct must be equal or below 1e18 as it represents 100%
  public fun pool_invalid_fee(): u64 { 14 }

  // Sender did not provide the same quantity of Yield and Principal
  public fun pool_mismatched_values(): u64 { 15 }

  // The sender tried to unstake more than he is allowed 
  public fun pool_invalid_stake_amount(): u64 { 16 }

  // User tried to redeem tokens before their maturity
  public fun pool_bond_not_matured(): u64 { 17 }

  // Sender tried to create a bond with an outdated maturity
  public fun pool_outdated_maturity(): u64 { 18 }

  // Sender tried to abuse the maturity 
  public fun pool_invalid_backup_maturity(): u64 { 19 }

  public fun pool_mismatched_maturity(): u64 { 20 }

  public fun review_on_cooldown(): u64 { 21 }

  public fun review_comment_too_long(): u64 { 22 }

  public fun user_already_reviewed(): u64 { 23 }

  public fun validator_not_reviewed(): u64 { 24 }

  public fun not_active_validator(): u64 { 25 }

  public fun sft_balance_mismatched_slot(): u64 { 26 }

  public fun sft_balance_invalid_split_amount(): u64 { 27 }

  public fun sft_balance_has_value(): u64 { 28 }

  public fun sft_supply_overflow(): u64 { 29 }

  public fun sft_cannot_divide_zero_value(): u64 { 30 }

  public fun sft_cannot_divide_into_zero(): u64 { 31 }

  public fun amm_not_enough_principal(): u64 { 32 }

  public fun amm_pool_already_exists(): u64 { 33 }
}