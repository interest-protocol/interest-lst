// Module has the logic on the dominance fee rate
module interest_lsd::fee_utils {

  use interest_lsd::math::{fmul, fdiv};

  // Formula is
  // dominance = validator_principal / total_principal
  // If the dominance >= kink
  // Fee = ((dominance - kink) * jump) + (kink * base)
  // Fee = dominance * base
  struct Fee has store {
    base: u256, // Base Multiplier
    kink: u256, // Threshold
    jump: u256 // Jump Multiplier
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
    principal: u256,
    total_principal: u256
  ): u256 {
    
    if (fee.base == 0) return 0;

    let dominance = fdiv(principal, total_principal);

    if (fee.kink >= dominance) return fmul(dominance, fee.base);

    fmul(dominance - fee.kink, fee.jump) + fmul(fee.kink, fee.base)
  }

  public fun set_fee(
    fee: &mut Fee,
    base: u256,
    kink: u256,
    jump: u256
  ) {
    fee.base = base;
    fee.kink = kink;
    fee.jump = jump;
  }

  #[test_only]
  public fun read_fee(fee:&Fee): (u256, u256, u256) {
    (fee.base, fee.kink, fee.jump)
  }

}