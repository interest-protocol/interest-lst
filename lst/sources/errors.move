module interest_lst::errors {
  public fun unstake_utils_mismatched_length(): u64 { 12 }

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

  public fun no_exchange_rate_found(): u64 { 21 }

  public fun invalid_version(): u64 { 22 }
}