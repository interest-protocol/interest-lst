// Sui Liquid Staking Principal Coin
// 1 ISUI_PC is always 1 SUI
module interest_lsd::isui_pc {
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
  struct ISUI_PC has drop {}

  // Treasury Cap Wrapper
  struct InterestISuiPCStorage has key {
    id: UID,
    treasury_cap: TreasuryCap<ISUI_PC>,
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

  fun init(witness: ISUI_PC, ctx: &mut TxContext) {
      // Create the ISUI_PC LSD coin
      let (treasury_cap, metadata) = coin::create_currency<ISUI_PC>(
            witness, 
            9,
            b"iSUI-PT",
            b"Interest Sui Principal Coin",
            b"This coin represents your principal on the Interest LSD Pool",
            option::none(),
            ctx
        );

      // Share the InterestSuiPCStorage Object with the Sui network
      transfer::share_object(
        InterestISuiPCStorage {
          id: object::new(ctx),
          treasury_cap,
        }
      );

      // Share the metadata object 
      transfer::public_share_object(metadata);
  }

  /**
  * @dev Only friend packages can mint ISUI_PC
  * @param storage The InterestSuiPCStorage
  * @param value The amount of ISUI_PC to mint
  * @return Coin<ISUI_PC> New created ISUI_PC coin
  */
  public(friend) fun mint(storage: &mut InterestISuiPCStorage, value: u64, ctx: &mut TxContext): Coin<ISUI_PC> {
    emit(Mint { amount: value, user: tx_context::sender(ctx) });
    coin::mint(&mut storage.treasury_cap, value, ctx)
  }

  /**
  * @dev Only friend packages can burn ISUI_PC
  * @param storage The InterestSuiPCStorage
  * @param asset The Coin to Burn out of existence
  * @return u64 The value burned
  */
  public(friend) fun burn(storage: &mut InterestISuiPCStorage, asset: Coin<ISUI_PC>, ctx: &mut TxContext): u64 {
    emit(Burn { amount: coin::value(&asset), user: tx_context::sender(ctx) });
    coin::burn(&mut storage.treasury_cap, asset)
  }

  /**
  * @dev Utility function to transfer Coin<ISUI_PC>
  * @param The coin to transfer
  * @param recipient The address that will receive the Coin<ISUI_PC>
  */
  public entry fun transfer(asset: coin::Coin<ISUI_PC>, recipient: address) {
    transfer::public_transfer(asset, recipient);
  }

  /**
  * It allows anyone to know the total value in existence of ISUI_PC
  * @storage The shared ISUI_PCollarStorage
  * @return u64 The total value of ISUI_PC in existence
  */
  public fun total_supply(storage: &InterestISuiPCStorage): u64 {
    coin::total_supply(&storage.treasury_cap)
  }

  // ** Admin Functions - The admin can only update the Metadata

  /// Update name of the coin in `CoinMetadata`
  public entry fun update_name(
        _: &AdminCap, storage: &InterestISuiPCStorage, metadata: &mut CoinMetadata<ISUI_PC>, name: string::String
    ) {
        coin::update_name(&storage.treasury_cap, metadata, name)
    }

    /// Update the symbol of the coin in `CoinMetadata`
    public entry fun update_symbol(
        _: &AdminCap, storage: &InterestISuiPCStorage, metadata: &mut CoinMetadata<ISUI_PC>, symbol: ascii::String
    ) {
       coin::update_symbol(&storage.treasury_cap, metadata, symbol)
    }

    /// Update the description of the coin in `CoinMetadata`
    public entry fun update_description(
        _: &AdminCap, storage: &InterestISuiPCStorage, metadata: &mut CoinMetadata<ISUI_PC>, description: string::String
    ) {
        coin::update_description(&storage.treasury_cap, metadata, description)
    }

    /// Update the url of the coin in `CoinMetadata`
    public entry fun update_icon_url(
        _: &AdminCap, storage: &InterestISuiPCStorage, metadata: &mut CoinMetadata<ISUI_PC>, url: ascii::String
    ) {
        coin::update_icon_url(&storage.treasury_cap, metadata, url)
    }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ISUI_PC {}, ctx);
  }
}