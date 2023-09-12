#[test_only]
module interest_lst::test_utils {
  
  use sui::test_scenario::{Self as test, Scenario};
  use sui::coin::{mint_for_testing, Coin};
  use sui::tx_context::{TxContext};
  use sui::math;

  public fun scenario(): Scenario { test::begin(@0x1) }

  public fun people():(address, address) { (@0xBEEF, @0x1337)}

  public fun mint<T>(amount: u64, decimals: u8, ctx: &mut TxContext): Coin<T> {
    mint_for_testing<T>(add_decimals(amount, decimals), ctx)
  }

  public fun add_decimals(amount: u64, decimals: u8): u64 {
    amount * math::pow(10, decimals)
  } 
}