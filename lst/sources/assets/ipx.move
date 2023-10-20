// Interest Protocol Governance Token
// TODO add DAO logic to handle access to the treasury
// TODO DECIDE ON INITIAL MINT
module interest_lst::ipx {
  use std::option::some;

  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::url::new_unsafe_from_bytes;
  use sui::tx_context::{sender, TxContext};
  use sui::coin::{Self, TreasuryCap};

  const TOTAL_SUPPLY: u64 = 1_000_000_000_000_000_000; // 1 Billion

  // OTW to create the Interest Sui lst
  struct IPX has drop {}

  struct TreasuryWrapper has key {
    id: UID,
    treasury: TreasuryCap<IPX>
  }

  fun init(witness: IPX, ctx: &mut TxContext) {
      let (treasury, metadata) = coin::create_currency<IPX>(
            witness, 
            9,
            b"IPX",
            b"Interest Protocol Token",
            b"The governance token of Interest Protocol",
            some(new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmcNYZn1urSEXBiZi2SiFzyeQcfNmTfHDU4kZLxhpCTRUK")),
            ctx
        );

      transfer::public_freeze_object(metadata);

      let total_ipx = coin::mint(&mut treasury, TOTAL_SUPPLY, ctx);
      transfer::public_transfer(total_ipx, sender(ctx));
      transfer::share_object(TreasuryWrapper { id: object::new(ctx), treasury });
  }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(IPX {}, ctx);
  }
}