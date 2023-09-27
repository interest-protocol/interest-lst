// Sui Liquid Staking Derivative Coin
// A share of all the rewards + principal in Interest lst Pool
module interest_tokens::isui {
  use std::ascii;
  use std::option;
  use std::string;

  use sui::url;
  use sui::transfer;
  use sui::event::emit;
  use sui::package::Publisher;
  use sui::object::{Self, UID, ID};
  use sui::vec_set::{Self, VecSet};
  use sui::tx_context::{Self, TxContext};
  use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};

  use access::admin::AdminCap;

  // Errors
  const EInvalidMinter: u64 = 0;

  // ** Structs

  // OTW to create the Interest Sui lst
  struct ISUI has drop {}

  // Treasury Cap Wrapper
  struct InterestSuiStorage has key {
    id: UID,
    treasury_cap: TreasuryCap<ISUI>,
    minters: VecSet<ID> 
  }

  // ** Events

  struct Mint has copy, drop {
    amount: u64,
    user: address
  }

  struct Burn has copy, drop {
    amount: u64,
    user: address
  }

  struct MinterAdded has copy, drop {
    id: ID
  }

  struct MinterRemoved has copy, drop {
    id: ID
  }

  fun init(witness: ISUI, ctx: &mut TxContext) {
      // Create the ISUI lst coin
      let (treasury_cap, metadata) = coin::create_currency<ISUI>(
            witness, 
            9,
            b"iSUI",
            b"Interest Sui",
            b"This coin represents your share on the Interest LST Pool",
            option::some(url::new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmPGCeoDN89GJwbKrY6ocxYUk8byYeDCCpJU2doSdgoDww")),
            ctx
        );

      // Share the InterestSuiStorage Object with the Sui network
      transfer::share_object(
        InterestSuiStorage {
          id: object::new(ctx),
          treasury_cap,
          minters: vec_set::empty()
        }
      );

      // Share the metadata object 
      transfer::public_share_object(metadata);
  }

  /**
  * @param storage The InterestSuiStorage
  * @param value The amount of ISUI to mint
  * @return Coin<ISUI> New created ISUI coin
  */
  public fun mint(storage: &mut InterestSuiStorage, publisher: &Publisher, value: u64, ctx: &mut TxContext): Coin<ISUI> {
    assert!(is_minter(storage, object::id(publisher)), EInvalidMinter);
    emit(Mint { amount: value, user: tx_context::sender(ctx) });
    coin::mint(&mut storage.treasury_cap, value, ctx)
  }

  /**
  * @param storage The InterestSuiStorage
  * @param asset The Coin to Burn out of existence
  * @return u64 The value burned
  */
  public fun burn(storage: &mut InterestSuiStorage, publisher: &Publisher, asset: Coin<ISUI>, ctx: &mut TxContext): u64 {
    assert!(is_minter(storage, object::id(publisher)), EInvalidMinter);
    emit(Burn { amount: coin::value(&asset), user: tx_context::sender(ctx) });
    coin::burn(&mut storage.treasury_cap, asset)
  }

  /**
  * @dev Utility function to transfer Coin<ISUI>
  * @param The coin to transfer
  * @param recipient The address that will receive the Coin<ISUI>
  */
  public entry fun transfer(asset: coin::Coin<ISUI>, recipient: address) {
    transfer::public_transfer(asset, recipient);
  }

  /**
  * It allows anyone to know the total value in existence of ISUI
  * @storage The shared ISUIollarStorage
  * @return u64 The total value of ISUI in existence
  */
  public fun total_supply(storage: &InterestSuiStorage): u64 {
    coin::total_supply(&storage.treasury_cap)
  }

  // ** Minter Functions - The admin can only update the Metadata

  entry public fun add_minter(_: &AdminCap, storage: &mut InterestSuiStorage, id: ID) {
    vec_set::insert(&mut storage.minters, id);
    emit(
      MinterAdded {
        id
      }
    );
  }

  entry public fun remove_minter(_: &AdminCap, storage: &mut InterestSuiStorage, id: ID) {
    vec_set::remove(&mut storage.minters, &id);
    emit(
      MinterRemoved {
        id
      }
    );
  } 

  public fun is_minter(storage: &InterestSuiStorage, id: ID): bool {
    vec_set::contains(&storage.minters, &id)
  }

  // ** Admin Functions - The admin can only update the Metadata

  /// Update name of the coin in `CoinMetadata`
  public entry fun update_name(
        _: &AdminCap, storage: &InterestSuiStorage, metadata: &mut CoinMetadata<ISUI>, name: string::String
    ) {
        coin::update_name(&storage.treasury_cap, metadata, name)
    }

    /// Update the symbol of the coin in `CoinMetadata`
    public entry fun update_symbol(
        _: &AdminCap, storage: &InterestSuiStorage, metadata: &mut CoinMetadata<ISUI>, symbol: ascii::String
    ) {
      coin::update_symbol(&storage.treasury_cap, metadata, symbol)
    }

    /// Update the description of the coin in `CoinMetadata`
    public entry fun update_description(
        _: &AdminCap, storage: &InterestSuiStorage, metadata: &mut CoinMetadata<ISUI>, description: string::String
    ) {
        coin::update_description(&storage.treasury_cap, metadata, description)
    }

    /// Update the url of the coin in `CoinMetadata`
    public entry fun update_icon_url(
        _: &AdminCap, storage: &InterestSuiStorage, metadata: &mut CoinMetadata<ISUI>, url: ascii::String
    ) {
        coin::update_icon_url(&storage.treasury_cap, metadata, url)
    }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ISUI {}, ctx);
  }
}