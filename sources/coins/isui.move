// Sui Liquid Staking Derivative Coin
// A share of all the rewards + principal in Interest LSD Pool
module interest_lsd::isui {
  use std::option;
  use std::string;
  use std::ascii;

  use sui::object::{Self, UID};
  use sui::tx_context::{TxContext};
  use sui::transfer;
  use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
  use sui::tx_context;
  use sui::event::{emit};

  use interest_lsd::admin::{AdminCap};

  // ** Only module that can mint/burn this coin
  friend interest_lsd::pool;

  // ** Structs

  // OTW to create the Interest Sui LSD
  struct ISUI has drop {}

  // Treasury Cap Wrapper
  struct InterestSuiStorage has key {
    id: UID,
    treasury_cap: TreasuryCap<ISUI>,
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

  fun init(witness: ISUI, ctx: &mut TxContext) {
      // Create the ISUI LSD coin
      let (treasury_cap, metadata) = coin::create_currency<ISUI>(
            witness, 
            9,
            b"iSUI",
            b"Interest Sui",
            b"This coin represents your share on the Interest LSD Pool",
            option::none(),
            ctx
        );

      // Share the InterestSuiStorage Object with the Sui network
      transfer::share_object(
        InterestSuiStorage {
          id: object::new(ctx),
          treasury_cap,
        }
      );

      // Share the metadata object 
      transfer::public_share_object(metadata);
  }

  /**
  * @dev Only friend packages can mint ISUI
  * @param storage The InterestSuiStorage
  * @param value The amount of ISUI to mint
  * @return Coin<ISUI> New created ISUI coin
  */
  public(friend) fun mint(storage: &mut InterestSuiStorage, value: u64, ctx: &mut TxContext): Coin<ISUI> {
    emit(Mint { amount: value, user: tx_context::sender(ctx) });
    coin::mint(&mut storage.treasury_cap, value, ctx)
  }

  /**
  * @dev Only friend packages can burn ISUI
  * @param storage The InterestSuiStorage
  * @param asset The Coin to Burn out of existence
  * @return u64 The value burned
  */
  public(friend) fun burn(storage: &mut InterestSuiStorage, asset: Coin<ISUI>, ctx: &mut TxContext): u64 {
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