module interest_lst::amm_utils {

  use sui::tx_context::{Self, TxContext};

  use interest_lst::errors;
  use interest_lst::constants;
  use interest_lst::fixed_point64::{Self, FixedPoint64};

  public fun get_safe_n(maturity: u64, ctx: &mut TxContext): u64 {
    let current_epoch = tx_context::epoch(ctx);

    if (current_epoch >= maturity) { 0 } else { maturity - current_epoch }
  }

  public fun create_r(numerator: u128): FixedPoint64 {
    // Cannot be higher than 20%
    assert!(constants::max_n_numerator() >= numerator, errors::amm_invalid_r());
    fixed_point64::create_from_rational(numerator,  constants::n_denominator())
  }
}