module interest_lst::errors {

  const EUnstakeUtilsMismatchedLength: u64 = 0;
  const EPoolInvalidFee: u64 = 1;
  const EPoolMistmatchedValues: u64 = 2;
  const EPoolInvalidStakeAmount: u64 = 3;
  const EPoolBondNotMatured: u64 = 4;
  const EPoolOutdatedMaturity: u64 = 5;
  const EPoolInvalidBackupMaturity: u64 = 6;
  const EPoolMismatchedMaturity: u64 = 7;
  const ENoExchangeRateFound: u64 = 8;
  const EInvalidVersion: u64 = 9;

  public fun unstake_utils_mismatched_length(): u64 { EUnstakeUtilsMismatchedLength }

  // All values inside the Fees Struct must be equal or below 1e18 as it represents 100%
  public fun pool_invalid_fee(): u64 { EPoolInvalidFee }

  // Sender did not provide the same quantity of Yield and Principal
  public fun pool_mismatched_values(): u64 { EPoolMistmatchedValues }

  // The sender tried to unstake more than he is allowed 
  public fun pool_invalid_stake_amount(): u64 { EPoolInvalidStakeAmount }

  // User tried to redeem tokens before their maturity
  public fun pool_bond_not_matured(): u64 { EPoolBondNotMatured }

  // Sender tried to create a bond with an outdated maturity
  public fun pool_outdated_maturity(): u64 { EPoolOutdatedMaturity }

  // Sender tried to abuse the maturity 
  public fun pool_invalid_backup_maturity(): u64 { EPoolInvalidBackupMaturity }

  public fun pool_mismatched_maturity(): u64 { EPoolMismatchedMaturity }

  public fun no_exchange_rate_found(): u64 { ENoExchangeRateFound }

  public fun invalid_version(): u64 { EInvalidVersion }
}