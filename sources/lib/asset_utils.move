// Utility module to deal with a vector of Coins and Coins with Zero Value
module interest_lst::asset_utils {
  use std::vector;
  
  use sui::pay;
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};
  
  use interest_lst::sui_yield::{Self, SuiYield};
  use interest_lst::sui_principal::SUI_PRINCIPAL;
  use interest_lst::semi_fungible_token::{Self as sfa, SemiFungibleToken};

  public  fun handle_coin_vector<X>(
      vector_x: vector<Coin<X>>,
      coin_in_value: u64,
      ctx: &mut TxContext
  ): Coin<X> {
      let coin_x = coin::zero<X>(ctx);

      if (vector::is_empty(&vector_x)) {
        vector::destroy_empty(vector_x);
        return coin_x
      };

      pay::join_vec(&mut coin_x, vector_x);

      let coin_x_value = coin::value(&coin_x);
      if (coin_x_value > coin_in_value) pay::split_and_transfer(&mut coin_x, coin_x_value - coin_in_value, tx_context::sender(ctx), ctx);

      coin_x
    }

  public fun public_transfer_coin<T>(asset: Coin<T>, recipient: address) {
      if (coin::value(&asset) == 0) {
        coin::destroy_zero(asset);
      } else {
        transfer::public_transfer(asset, recipient);
      }
  }

  public fun public_transfer_yield(asset: SuiYield, recipient: address) {
      if (sui_yield::value(&asset) == 0) {
        sui_yield::destroy_zero(asset);
      } else {
        transfer::public_transfer(asset, recipient);
      }
  }

  public fun public_transfer_principal(asset: SemiFungibleToken<SUI_PRINCIPAL>, recipient: address) {
      if (sfa::value(&asset) == 0) {
        sfa::destroy_zero(asset);
      } else {
        transfer::public_transfer(asset, recipient);
      }
  }

  public fun handle_principal_vector(
    vector_asset: vector<SemiFungibleToken<SUI_PRINCIPAL>>,
    asset_in_value: u64,
    ctx: &mut TxContext
  ): SemiFungibleToken<SUI_PRINCIPAL> {

    let index = 0;
   
    let asset = vector::pop_back(&mut vector_asset);
    let len = vector::length(&vector_asset);
    let total_value = sfa::value(&asset);

    while (len > index) {
      let other_asset = vector::pop_back(&mut vector_asset);
      
      total_value = total_value + sfa::value(&other_asset);

      sfa::join(&mut asset, other_asset);

      index = index + 1;
    };

    if (total_value > asset_in_value)
      transfer::transfer(sfa::split(&mut asset, total_value - asset_in_value, ctx),tx_context::sender(ctx));

    asset
  }

  public fun handle_yield_vector(
    vector_asset: vector<SuiYield>,
    asset_in_value: u64,
    ctx: &mut TxContext
  ): SuiYield {

    let index = 0;
   
    let asset = vector::pop_back(&mut vector_asset);
    let len = vector::length(&vector_asset);
    let total_value = sui_yield::value(&asset);

    while (len > index) {
      let other_asset = vector::pop_back(&mut vector_asset);
      
      total_value = total_value + sui_yield::value(&other_asset);

      sui_yield::join(&mut asset, other_asset);

      index = index + 1;
    };

    if (total_value > asset_in_value)
      transfer::transfer(sui_yield::split(&mut asset, total_value - asset_in_value, ctx),tx_context::sender(ctx));

    asset
  }
}