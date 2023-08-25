// Access Control for Interest LSD package
module interest_lsd::admin {

  use sui::object::{Self, UID};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::event::{emit};

  // The owner of this object can add and remove minters + update the metadata
  struct AdminCap has key {
    id: UID
  }

  struct NewAdmin has copy, drop {
    admin: address
  }

  const ERROR_NO_ZERO_ADDRESS: u64 = 0;

  fun init(ctx: &mut TxContext) {

      // Send the AdminCap to the deployer
      transfer::transfer(
        AdminCap {
          id: object::new(ctx)
        },
        tx_context::sender(ctx)
      );
  }

 /**
  * @dev It gives the admin rights to the recipient. 
  * @param admin_cap The AdminCap that will be transferred
  * @recipient the new admin address
  *
  * It emits the NewAdmin event with the new admin address
  *
  */
  entry public fun transfer_admin(admin_cap: AdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_NO_ZERO_ADDRESS);
    transfer::transfer(admin_cap, recipient);

    emit(NewAdmin {
      admin: recipient
    });
  } 

}