// Module has the logic on the dominance fee rate
module interest_lst::fee_utils {

  use interest_lst::math::{fmul, fdiv};

  // Formula is
  // dominance = validator_principal / total_principal
  // If the dominance >= kink
  // Fee = ((dominance - kink) * jump) + (kink * base)
  // Fee = dominance * base
  struct Fee has store {
    base: u128, // Base Multiplier
    kink: u128, // Threshold
    jump: u128 // Jump Multiplier
  }

  public fun new(): Fee {
    Fee {
      base: 0,
      kink: 0,
      jump: 0
    }
  }

  public fun calculate_fee_percentage(
    fee: &Fee,
    principal: u128,
    total_principal: u128
  ): u128 {
    
    // Avoid zero division as if the principal >= 0 - the total_principal is also >= 0
    // If the validator does not have any principal, there is no fee associated
    if (fee.base == 0 || principal == 0) return 0;

    let dominance = fdiv(principal, total_principal);

    if (fee.kink >= dominance) return fmul(dominance, fee.base);

    fmul(dominance - fee.kink, fee.jump) + fmul(fee.kink, fee.base)
  }

  public fun set_fee(
    fee: &mut Fee,
    base: u128,
    kink: u128,
    jump: u128
  ) {
    fee.base = base;
    fee.kink = kink;
    fee.jump = jump;
  }

  #[test_only]
  public fun read_fee(fee:&Fee): (u128, u128, u128) {
    (fee.base, fee.kink, fee.jump)
  }
}