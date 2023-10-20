// Interest Protocol Governance Token
module interest_lst::ipx {
  use std::option::some;

  use sui::url::new_unsafe_from_bytes;
  use sui::tx_context::{sender, TxContext};
  use sui::balance::{increase_supply, destroy_supply};
  use sui::transfer::{public_freeze_object, transfer};
  use sui::coin::{create_currency, treasury_into_supply};

  const TOTAL_SUPPLY: u64 = 1_000_000_000_000_000_000; // 1 Billion

  // OTW to create the Interest Sui lst
  struct IPX has drop {}

  fun init(witness: IPX, ctx: &mut TxContext) {
      let (treasury_cap, metadata) = create_currency<IPX>(
            witness, 
            9,
            b"IPX",
            b"Interest Protocol Token",
            b"The governance token of Interest Protocol",
            option::some(url::new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmcNYZn1urSEXBiZi2SiFzyeQcfNmTfHDU4kZLxhpCTRUK")),
            ctx
        );

      public_freeze_object(metadata);
      let supply = treasury_into_supply(treasury);
      let total_ipx = increase_supply(&mut supply, TOTAL_SUPPLY);
      destroy_supply(supply);
      transfer(total_ipx, sender(ctx));
  }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(IPX {}, ctx);
  }
}