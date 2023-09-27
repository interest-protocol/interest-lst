module interest_lst::unstake_utils { 
  use std::vector;

  use interest_lst::errors;

  struct EpochAmount has store, copy, drop {
    epoch: u64,
    amount: u64,
    split: bool
  }

  struct UnstakePayload has store, copy, drop {
    validator: address,
    amounts: vector<EpochAmount>
  }

  public fun read_unstake_payload(self: &UnstakePayload): (address, &vector<EpochAmount>) {
    (self.validator, &self.amounts)
  }

  public fun read_epoch_amount(self: &EpochAmount): (u64, u64, bool) {
    (self.epoch, self.amount, self.split)
  }

  public fun make_epoch_amount_vector(epochs: vector<u64>, amounts: vector<u64>, splits: vector<bool>): vector<EpochAmount> {
    let len = vector::length(&epochs);
    assert!(len == vector::length(&amounts), errors::unstake_utils_mismatched_length());
    let data = vector::empty();

    let i = 0;
    while (len > i) {
      let epoch = *vector::borrow(&epochs, i);
      let amount = *vector::borrow(&amounts, i);
      let split = *vector::borrow(&splits, i);

      vector::push_back(&mut data, EpochAmount { epoch, amount, split });

      i = i + 1;
    };

    data
  }

  public fun make_epoch_amount(epoch: u64, amount: u64, split: bool): EpochAmount {
    EpochAmount {
      epoch,
      amount,
      split
    }
  }

  public fun make_unstake_payload(validator: address, amounts: vector<EpochAmount>): UnstakePayload {
    UnstakePayload {
      validator,
      amounts
    }
  }

  public fun update_unstake_payload_amounts(self: &mut UnstakePayload): &mut vector<EpochAmount> {
    &mut self.amounts
  }
}