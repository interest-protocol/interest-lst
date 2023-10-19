// Utility module to deal with a vector of Coins and Coins with Zero Value
module interest_lst::asset_utils {
  use std::vector;
  
  use sui::pay;
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};

  use yield::yield::{Self, Yield};

  use suitears::semi_fungible_token::{Self as sft, SemiFungibleToken};
  
  use interest_lst::isui_yield::ISUI_YIELD;
  use interest_lst::isui_principal::ISUI_PRINCIPAL;

  public  fun handle_coin_vector<T>(
      vector_coin: vector<Coin<T>>,
      coin_in_value: u64,
      ctx: &mut TxContext
  ): Coin<T> {
      let asset = coin::zero<T>(ctx);

      if (vector::is_empty(&vector_coin)) {
        vector::destroy_empty(vector_coin);
        return asset
      };

      pay::join_vec(&mut asset, vector_coin);

      let asset_value = coin::value(&asset);
      if (asset_value > coin_in_value) pay::split_and_transfer(&mut asset, asset_value - coin_in_value, tx_context::sender(ctx), ctx);

      asset
    }

  public fun public_transfer_coin<T>(asset: Coin<T>, recipient: address) {
      if (coin::value(&asset) == 0) {
        coin::destroy_zero(asset);
      } else {
        transfer::public_transfer(asset, recipient);
      }
  }

  public fun public_transfer_yield(asset: Yield<ISUI_YIELD>, recipient: address) {
      if (yield::value(&asset) == 0) {
        yield::burn_zero(asset);
      } else {
        transfer::public_transfer(asset, recipient);
      }
  }

  public fun public_transfer_principal(asset: SemiFungibleToken<ISUI_PRINCIPAL>, recipient: address) {
      if (sft::value(&asset) == 0) {
        sft::burn_zero(asset);
      } else {
        transfer::public_transfer(asset, recipient);
      }
  }

  public fun handle_principal_vector(
    vector_asset: vector<SemiFungibleToken<ISUI_PRINCIPAL>>,
    asset_in_value: u64,
    ctx: &mut TxContext
  ): SemiFungibleToken<ISUI_PRINCIPAL> {

    let index = 0;
   
    let asset = vector::pop_back(&mut vector_asset);
    let len = vector::length(&vector_asset);
    let total_value = sft::value(&asset);

    while (len > index) {
      let other_asset = vector::pop_back(&mut vector_asset);
      
      total_value = total_value + sft::value(&other_asset);

      sft::join(&mut asset, other_asset);

      index = index + 1;
    };

    vector::destroy_empty(vector_asset);

    if (total_value > asset_in_value)
      transfer::public_transfer(sft::split(&mut asset, total_value - asset_in_value, ctx),tx_context::sender(ctx));

    asset
  }

  public fun handle_yield_vector(
    vector_asset: vector<Yield<ISUI_YIELD>>,
    asset_in_value: u64,
    ctx: &mut TxContext
  ): Yield<ISUI_YIELD> {

    let index = 0;
   
    let asset = vector::pop_back(&mut vector_asset);
    let len = vector::length(&vector_asset);
    let total_value = yield::value(&asset);

    while (len > index) {
      let other_asset = vector::pop_back(&mut vector_asset);
      
      total_value = total_value + yield::value(&other_asset);

      yield::join(&mut asset, other_asset);

      index = index + 1;
    };

    vector::destroy_empty(vector_asset);

    if (total_value > asset_in_value)
      transfer::public_transfer(yield::split(&mut asset, total_value - asset_in_value, ctx),tx_context::sender(ctx));

    asset
  }
}