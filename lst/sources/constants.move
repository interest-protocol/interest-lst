module interest_lst::constants {

  const MIN_STAKE_AMOUNT: u64 = 1_000_000_000;

  public fun min_stake_amount(): u64 {
    MIN_STAKE_AMOUNT
  }
}