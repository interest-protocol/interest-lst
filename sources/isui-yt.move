// Sui Liquid Staking Derivative Coin
module interest_lsd::isui_yt {
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

  const ERROR_WRONG_FLASH_MINT_BURN_AMOUNT: u64 = 0;

  // ** Structs

  // OTW to create the Interest Sui LSD
  struct ISUI_YT has drop {}

  // Treasury Cap Wrapper
  struct InterestSuiYTStorage has key {
    id: UID,
    treasury_cap: TreasuryCap<ISUI_YT>,
  }

  // ** IMPORTANT DO NOT ADD ABILITIES
  struct Debt {
    amount: u64
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

  struct FlashMint has copy, drop {
    borrower: address,
    amount: u64
  }

  struct FlashBurn has copy, drop {
    borrower: address,
    amount: u64
  }

  fun init(witness: ISUI_YT, ctx: &mut TxContext) {
      // Create the ISUI_YT LSD coin
      let (treasury_cap, metadata) = coin::create_currency<ISUI_YT>(
            witness, 
            9,
            b"iSUI-PT",
            b"Interest Sui Principal Token",
            b"This coin represents your principal on the Interest LSD Pool",
            option::none(),
            ctx
        );

      // Share the InterestSuiYTStorage Object with the Sui network
      transfer::share_object(
        InterestSuiYTStorage {
          id: object::new(ctx),
          treasury_cap,
        }
      );

      // Share the metadata object 
      transfer::public_share_object(metadata);
  }

  /**
  * @dev Only friend packages can mint ISUI_YT
  * @param storage The InterestSuiYTStorage
  * @param value The amount of ISUI_YT to mint
  * @return Coin<ISUI_YT> New created ISUI_YT coin
  */
  public(friend) fun mint(storage: &mut InterestSuiYTStorage, value: u64, ctx: &mut TxContext): Coin<ISUI_YT> {
    emit(Mint { amount: value, user: tx_context::sender(ctx) });
    coin::mint(&mut storage.treasury_cap, value, ctx)
  }

  /**
  * @dev Only friend packages can burn ISUI_YT
  * @param storage The InterestSuiYTStorage
  * @param asset The Coin to Burn out of existence
  * @return u64 The value burned
  */
  public(friend) fun burn(storage: &mut InterestSuiYTStorage, asset: Coin<ISUI_YT>, ctx: &mut TxContext): u64 {
    emit(Burn { amount: coin::value(&asset), user: tx_context::sender(ctx) });
    coin::burn(&mut storage.treasury_cap, asset)
  }

  public fun flash_mint(storage: &mut InterestSuiYTStorage, value: u64, ctx: &mut TxContext): (Debt, Coin<ISUI_YT>) {
    emit(FlashMint { amount: value, borrower: tx_context::sender(ctx) });
    (Debt { amount: value }, coin::mint(&mut storage.treasury_cap, value, ctx))
  }

  public fun read_debt(potato: &Debt): u64 {
    potato.amount
  }

  public fun flash_burn(storage: &mut InterestSuiYTStorage, potato: Debt, asset: Coin<ISUI_YT>, ctx: &mut TxContext) {
    let Debt { amount } = potato;
    
    // We need to make sure the supply remains the same
    assert!(coin::value(&asset) == amount, ERROR_WRONG_FLASH_MINT_BURN_AMOUNT);
    coin::burn(&mut storage.treasury_cap, asset);
    emit(FlashBurn { amount, borrower: tx_context::sender(ctx) });
  }

  /**
  * @dev Utility function to transfer Coin<ISUI_YT>
  * @param The coin to transfer
  * @param recipient The address that will receive the Coin<ISUI_YT>
  */
  public entry fun transfer(asset: coin::Coin<ISUI_YT>, recipient: address) {
    transfer::public_transfer(asset, recipient);
  }

  /**
  * It allows anyone to know the total value in existence of ISUI_YT
  * @storage The shared ISUI_YTollarStorage
  * @return u64 The total value of ISUI_YT in existence
  */
  public fun total_supply(storage: &InterestSuiYTStorage): u64 {
    coin::total_supply(&storage.treasury_cap)
  }

  // ** Admin Functions - The admin can only update the Metadata

  /// Update name of the coin in `CoinMetadata`
  public entry fun update_name(
        _: &AdminCap, storage: &InterestSuiYTStorage, metadata: &mut CoinMetadata<ISUI_YT>, name: string::String
    ) {
        coin::update_name(&storage.treasury_cap, metadata, name)
    }

    /// Update the symbol of the coin in `CoinMetadata`
    public entry fun update_symbol(
        _: &AdminCap, storage: &InterestSuiYTStorage, metadata: &mut CoinMetadata<ISUI_YT>, symbol: ascii::String
    ) {
       coin::update_symbol(&storage.treasury_cap, metadata, symbol)
    }

    /// Update the description of the coin in `CoinMetadata`
    public entry fun update_description(
        _: &AdminCap, storage: &InterestSuiYTStorage, metadata: &mut CoinMetadata<ISUI_YT>, description: string::String
    ) {
        coin::update_description(&storage.treasury_cap, metadata, description)
    }

    /// Update the url of the coin in `CoinMetadata`
    public entry fun update_icon_url(
        _: &AdminCap, storage: &InterestSuiYTStorage, metadata: &mut CoinMetadata<ISUI_YT>, url: ascii::String
    ) {
        coin::update_icon_url(&storage.treasury_cap, metadata, url)
    }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ISUI_YT {}, ctx);
  }

  #[test_only]
  public fun mint_for_testing(storage: &mut InterestSuiYTStorage, value: u64, ctx: &mut TxContext): Coin<ISUI_YT> {
    coin::mint(&mut storage.treasury_cap, value, ctx)
  }
}