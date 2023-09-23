/*
* Title - Semi Fungible Token
*
* Balance representation of a Semi Fungible Token
*/
module interest_lst::semi_fungible_balance {

  use interest_lst::errors;

  struct SFTBalance<phantom T> has store {
      slot: u256,
      value: u64,
  }

  public fun slot<T>(self: &SFTBalance<T>): u256 {
    self.slot
  }

  public fun value<T>(self: &SFTBalance<T>): u64 {
    self.value
  }

  public fun zero<T>(slot: u256): SFTBalance<T> {
    SFTBalance { slot, value: 0 }
  }

  spec zero {
    aborts_if false;
    ensures result.value == 0;
  }

  public fun join<T>(self: &mut SFTBalance<T>, balance: SFTBalance<T>): u64 {
    let SFTBalance {slot, value } = balance;
    assert!(self.slot == slot, errors::sft_balance_mismatched_slot());
    self.value = self.value + value;
    self.value
  }

  spec join {
    aborts_if false;
    ensures self.value == old(self.value) + balance.value;
    ensures result == self.value;
    ensures self.slot == old(self.slot);
    ensures self.slot == balance.slot;
  }

  public fun split<T>(self: &mut SFTBalance<T>, value: u64): SFTBalance<T> {
    assert!(self.value >= value, errors::sft_balance_invalid_split_amount());
    self.value = self.value - value;
    SFTBalance {slot: self.slot, value }
  }

  spec split {
    aborts_if self.value < value with errors::sft_balance_invalid_split_amount();
    ensures self.value == old(self.value) - value;
    ensures result.value == value;
    ensures self.slot == result.slot;
  }

  public fun withdraw_all<T>(self: &mut SFTBalance<T>): SFTBalance<T> {
    let value = self.value;
    split(self, value)
  }

  spec withdraw_all {
    ensures self.value == 0;
    ensures result.value == old(self.value);
  }

  public fun destroy_zero<T>(self: SFTBalance<T>) {
    assert!(self.value == 0, errors::sft_balance_has_value());
    let SFTBalance {value: _, slot: _ } = self;
   }

  spec destroy_zero {
    aborts_if self.value != 0 with errors::sft_balance_has_value();
  }

  #[test_only]
  public fun create_for_testing<T>(slot: u256, value: u64): SFTBalance<T> {
    SFTBalance { slot, value }
  }

  #[test_only]
  public fun destroy_for_testing<T>(self: SFTBalance<T>): u64 {
    let SFTBalance { slot: _, value } = self;
    value
  }
}