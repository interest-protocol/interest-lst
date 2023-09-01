// Sui Liquid Staking Yield Coin
// A Share of the rewards accrued by Interest LSD Pool
module interest_lsd::isui_yc {
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
  struct ISUI_YC has drop {}

  // Treasury Cap Wrapper
  struct InterestSuiYCStorage has key {
    id: UID,
    treasury_cap: TreasuryCap<ISUI_YC>,
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

  fun init(witness: ISUI_YC, ctx: &mut TxContext) {
      // Create the ISUI_YC LSD coin
      let (treasury_cap, metadata) = coin::create_currency<ISUI_YC>(
            witness, 
            9,
            b"iSUI-YC",
            b"Interest Sui Yield Coin",
            b"This coin represents your yield on the Interest LSD Pool",
            option::none(),
            ctx
        );

      // Share the InterestSuiYCStorage Object with the Sui network
      transfer::share_object(
        InterestSuiYCStorage {
          id: object::new(ctx),
          treasury_cap,
        }
      );

      // Share the metadata object 
      transfer::public_share_object(metadata);
  }

  /**
  * @dev Only friend packages can mint ISUI_YC
  * @param storage The InterestSuiYCStorage
  * @param value The amount of ISUI_YC to mint
  * @return Coin<ISUI_YC> New created ISUI_YC coin
  */
  public(friend) fun mint(storage: &mut InterestSuiYCStorage, value: u64, ctx: &mut TxContext): Coin<ISUI_YC> {
    emit(Mint { amount: value, user: tx_context::sender(ctx) });
    coin::mint(&mut storage.treasury_cap, value, ctx)
  }

  /**
  * @dev Only friend packages can burn ISUI_YC
  * @param storage The InterestSuiYCStorage
  * @param asset The Coin to Burn out of existence
  * @return u64 The value burned
  */
  public(friend) fun burn(storage: &mut InterestSuiYCStorage, asset: Coin<ISUI_YC>, ctx: &mut TxContext): u64 {
    emit(Burn { amount: coin::value(&asset), user: tx_context::sender(ctx) });
    coin::burn(&mut storage.treasury_cap, asset)
  }

  /**
  * @dev Utility function to transfer Coin<ISUI_YC>
  * @param The coin to transfer
  * @param recipient The address that will receive the Coin<ISUI_YC>
  */
  public entry fun transfer(asset: coin::Coin<ISUI_YC>, recipient: address) {
    transfer::public_transfer(asset, recipient);
  }

  /**
  * It allows anyone to know the total value in existence of ISUI_YC
  * @storage The shared ISUI_YCollarStorage
  * @return u64 The total value of ISUI_YC in existence
  */
  public fun total_supply(storage: &InterestSuiYCStorage): u64 {
    coin::total_supply(&storage.treasury_cap)
  }

  // ** Admin Functions - The admin can only update the Metadata

  /// Update name of the coin in `CoinMetadata`
  public entry fun update_name(
        _: &AdminCap, storage: &InterestSuiYCStorage, metadata: &mut CoinMetadata<ISUI_YC>, name: string::String
    ) {
        coin::update_name(&storage.treasury_cap, metadata, name)
    }

    /// Update the symbol of the coin in `CoinMetadata`
    public entry fun update_symbol(
        _: &AdminCap, storage: &InterestSuiYCStorage, metadata: &mut CoinMetadata<ISUI_YC>, symbol: ascii::String
    ) {
       coin::update_symbol(&storage.treasury_cap, metadata, symbol)
    }

    /// Update the description of the coin in `CoinMetadata`
    public entry fun update_description(
        _: &AdminCap, storage: &InterestSuiYCStorage, metadata: &mut CoinMetadata<ISUI_YC>, description: string::String
    ) {
        coin::update_description(&storage.treasury_cap, metadata, description)
    }

    /// Update the url of the coin in `CoinMetadata`
    public entry fun update_icon_url(
        _: &AdminCap, storage: &InterestSuiYCStorage, metadata: &mut CoinMetadata<ISUI_YC>, url: ascii::String
    ) {
        coin::update_icon_url(&storage.treasury_cap, metadata, url)
    }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ISUI_YC {}, ctx);
  }
}