// * IMPORTANT This object will be stored in a DAO action module in the future
module interest_lst::lst_admin { 

  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::tx_context::{Self, TxContext};

  struct LstAdmin has key, store {
    id: UID
  }

  fun init(ctx: &mut TxContext) {
    transfer::transfer(
      LstAdmin { id: object::new(ctx) },
      tx_context::sender(ctx)
    );
  }
}