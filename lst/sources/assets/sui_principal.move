// Interest lst Staked Sui is a Semi-Fungible Coin  
// It represents an active deposit on the pool (NO YIELD - just the residue/principal)
module interest_lst::sui_principal {
  use std::option::some;

  use sui::transfer;
  use sui::url::new_unsafe_from_bytes;
  use sui::tx_context::{sender, TxContext};
  
  use suitears::semi_fungible_token::create_sft;


  // OTW to create the Staked Sui
  struct SUI_PRINCIPAL has drop {}

  fun init(witness: SUI_PRINCIPAL, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = create_sft(
      witness,
      9,
      b"iSUIP",
      b"Interest Sui Principal",
      b"It represents the principal of Native Staked Sui in the Interest LST pool", 
      b"The slot is the maturity epoch of this token.",
      some(new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/Qmc4veispLmhnGa2dGd3YFaj1GA12FniP8FMVzUEiijjme")),
      ctx
    );

    transfer::public_share_object(metadata);
    transfer::public_transfer(treasury_cap, sender(ctx));
  }

  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SUI_PRINCIPAL {}, ctx);
  }
}