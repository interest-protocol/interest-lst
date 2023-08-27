// Module has the logic on the dominance fee rate
// Formula is
// dominance = validator_principal / total_principal
// If the dominance >= kink
// Fee = ((dominance - kink) * jump) + (kink * base)
// Fee = dominance * base
module interest_lsd::fees_utils {

  use interest_lsd::math::{fmul, fdiv};

  public fun calculate_fee_percentage(
    base: u256,
    kink: u256,
    jump: u256,
    principal: u256,
    total_principal: u256
  ): u256 {
    
    if (base == 0) return 0;

    let dominance = fdiv(principal, total_principal);

    if (kink >= dominance) return fmul(dominance, base);

    fmul(dominance - kink, jump) + fmul(kink, base)
  }

}