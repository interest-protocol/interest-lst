module interest_lst::amm_utils {
  use sui::tx_context::{Self, TxContext};

  public fun get_safe_n(maturity: u64, ctx: &mut TxContext): u64 {
    let current_epoch = tx_context::epoch(ctx);

    if (current_epoch >= maturity) { 0 } else { maturity - current_epoch }
  }
}