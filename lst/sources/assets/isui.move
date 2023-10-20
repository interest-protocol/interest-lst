// Sui Liquid Staking Derivative Coin
// A share of all the rewards + principal in Interest lst Pool
module interest_lst::isui {
  use std::option::some;

  use sui::transfer;
  use sui::coin::create_currency;
  use sui::url::new_unsafe_from_bytes;
  use sui::tx_context::{sender, TxContext};

  // ** Structs

  // OTW to create the Interest Sui lst
  struct ISUI has drop {}

  fun init(witness: ISUI, ctx: &mut TxContext) {
      // Create the ISUI lst coin
      let (treasury_cap, metadata) = create_currency<ISUI>(
            witness, 
            9,
            b"iSUI",
            b"Interest Sui",
            b"This coin represents your share on the Interest LST Pool",
            some(new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmcE2kDkUdUBQ6PGnpQn44H2PKw1HFEhxJoNKSoygx1DK1")),
            ctx
        );

      // Share the metadata object 
      transfer::public_share_object(metadata);
      transfer::public_transfer(treasury_cap, sender(ctx));
  }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ISUI {}, ctx);
  }
}