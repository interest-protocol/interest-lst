// Interest Staked Sui
// It is a Coin backed by Sui with an exchange of 1:1
// 1 INTEREST_STAKED_SUI is always 1 SUI
#[test_only]
module interest_lsd::test_interest_staked_sui {
  // use std::ascii;
  // use std::option;
  // use std::string;

  // use sui::transfer;
  // use sui::event::{emit};
  // use sui::object::{Self, UID};
  // use sui::tx_context::{Self, TxContext};
  // use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};

  // use interest_lsd::admin::{AdminCap};

  // // ** Only module that can mint/burn this coin
  // friend interest_lsd::pool;

  // // ** Structs

  // // OTW to create the Interest Staked Sui
  // struct INTEREST_STAKED_SUI has drop {}

  // // Treasury Cap Wrapper
  // struct InterestStakedSuiStorage has key {
  //   id: UID,
  //   treasury_cap: TreasuryCap<INTEREST_STAKED_SUI>,
  // }

  // // ** Events

  // struct Mint has copy, drop {
  //   amount: u64,
  //   user: address
  // }

  // struct Burn has copy, drop {
  //   amount: u64,
  //   user: address
  // }

  // fun init(witness: INTEREST_STAKED_SUI, ctx: &mut TxContext) {
  //     // Create the INTEREST_STAKED_SUI LSD coin
  //     let (treasury_cap, metadata) = coin::create_currency<INTEREST_STAKED_SUI>(
  //           witness, 
  //           9,
  //           b"isSUI",
  //           b"Interest Staked Sui",
  //           b"This coin is pegged to Sui.",
  //           option::none(),
  //           ctx
  //       );

  //     // Share the InterestStakedSuiStorage Object with the Sui network
  //     transfer::share_object(
  //       InterestStakedSuiStorage {
  //         id: object::new(ctx),
  //         treasury_cap,
  //       }
  //     );

  //     // Share the metadata object 
  //     transfer::public_share_object(metadata);
  // }

  // /**
  // * @dev Only friend packages can mint INTEREST_STAKED_SUI
  // * @param storage The InterestStakedSuiStorage
  // * @param value The amount of INTEREST_STAKED_SUI to mint
  // * @return Coin<INTEREST_STAKED_SUI> New created INTEREST_STAKED_SUI coin
  // */
  // public(friend) fun mint(storage: &mut InterestStakedSuiStorage, value: u64, ctx: &mut TxContext): Coin<INTEREST_STAKED_SUI> {
  //   emit(Mint { amount: value, user: tx_context::sender(ctx) });
  //   coin::mint(&mut storage.treasury_cap, value, ctx)
  // }

  // /**
  // * @dev Only friend packages can burn INTEREST_STAKED_SUI
  // * @param storage The InterestStakedSuiStorage
  // * @param asset The Coin to Burn out of existence
  // * @return u64 The value burned
  // */
  // public(friend) fun burn(storage: &mut InterestStakedSuiStorage, asset: Coin<INTEREST_STAKED_SUI>, ctx: &mut TxContext): u64 {
  //   emit(Burn { amount: coin::value(&asset), user: tx_context::sender(ctx) });
  //   coin::burn(&mut storage.treasury_cap, asset)
  // }

  // /**
  // * @dev Utility function to transfer Coin<INTEREST_STAKED_SUI>
  // * @param The coin to transfer
  // * @param recipient The address that will receive the Coin<INTEREST_STAKED_SUI>
  // */
  // public entry fun transfer(asset: coin::Coin<INTEREST_STAKED_SUI>, recipient: address) {
  //   transfer::public_transfer(asset, recipient);
  // }

  // /**
  // * It allows anyone to know the total value in existence of INTEREST_STAKED_SUI
  // * @storage The shared InterestStakedSuiStorage
  // * @return u64 The total value of INTEREST_STAKED_SUI in existence
  // */
  // public fun total_supply(storage: &InterestStakedSuiStorage): u64 {
  //   coin::total_supply(&storage.treasury_cap)
  // }

  // // ** Admin Functions - The admin can only update the Metadata

  // /// Update name of the coin in `CoinMetadata`
  // public entry fun update_name(
  //       _: &AdminCap, storage: &InterestStakedSuiStorage, metadata: &mut CoinMetadata<INTEREST_STAKED_SUI>, name: string::String
  //   ) {
  //       coin::update_name(&storage.treasury_cap, metadata, name)
  //   }

  //   /// Update the symbol of the coin in `CoinMetadata`
  //   public entry fun update_symbol(
  //       _: &AdminCap, storage: &InterestStakedSuiStorage, metadata: &mut CoinMetadata<INTEREST_STAKED_SUI>, symbol: ascii::String
  //   ) {
  //     coin::update_symbol(&storage.treasury_cap, metadata, symbol)
  //   }

  //   /// Update the description of the coin in `CoinMetadata`
  //   public entry fun update_description(
  //       _: &AdminCap, storage: &InterestStakedSuiStorage, metadata: &mut CoinMetadata<INTEREST_STAKED_SUI>, description: string::String
  //   ) {
  //       coin::update_description(&storage.treasury_cap, metadata, description)
  //   }

  //   /// Update the url of the coin in `CoinMetadata`
  //   public entry fun update_icon_url(
  //       _: &AdminCap, storage: &InterestStakedSuiStorage, metadata: &mut CoinMetadata<INTEREST_STAKED_SUI>, url: ascii::String
  //   ) {
  //       coin::update_icon_url(&storage.treasury_cap, metadata, url)
  //   }

  // // ** Test Functions

  // #[test_only]
  // public fun init_for_testing(ctx: &mut TxContext) {
  //   init(INTEREST_STAKED_SUI {}, ctx);
  // }
}