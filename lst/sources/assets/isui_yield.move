// Sui Yield is a Wrapped SFT with extra information about the yield
// Reward paid is the rewards paid to date
// Principal was the original shares to create the yield
module interest_lst::isui_yield {
  use std::option::some;

  use sui::transfer;
  use sui::url::new_unsafe_from_bytes;
  use sui::tx_context::{sender, TxContext};

  use yield::yield::create;

  struct ISUI_YIELD has drop {}

  fun init(witness: ISUI_YIELD, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = create(
      witness,
      9,
      b"iSUIY",
      b"Interest Sui Yield",
      b"It represents the yield of Native Staked Sui in the Interest LST pool.", 
      b"The slot is the maturity epoch of this token",
      some(new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmcVgNciMdAqVzJ8uZUgibn2gvhMtKRdG6J2qNrB37LRFf")),
      ctx
    );

    transfer::public_share_object(metadata);
    transfer::public_transfer(treasury_cap, sender(ctx));
  }

  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ISUI_YIELD {}, ctx);
  }
}