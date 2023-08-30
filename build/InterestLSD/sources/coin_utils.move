// Utility module to deal with a vector of Coins and Coins with Zero Value
module interest_lsd::coin_utils {
  use std::vector;
  
  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};
  use sui::pay;
  use sui::transfer;

  public  fun handle_coin_vector<X>(
      vector_x: vector<Coin<X>>,
      coin_in_value: u64,
      ctx: &mut TxContext
  ): Coin<X> {
      let coin_x = coin::zero<X>(ctx);

      if (vector::is_empty(&vector_x)){
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
}