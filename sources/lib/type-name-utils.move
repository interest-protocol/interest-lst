// Module provides utility functions to construct custom String keys to add as dynamic fields
module interest_lsd::type_name_utils {
  use std::ascii::{Self, String}; 
  use std::vector;
  use std::type_name;

  public fun get_type_name_string<T>(): String {
    type_name::into_string(type_name::get<T>())
  }

  public fun get_coin_data_key(string: String): String {
    get_key(string, coin_data_key())
  }

  fun coin_data_key(): vector<u8> {
    b"-coin-data"
  }

  fun get_key(string: String, key: vector<u8>): String {
    let bytes = ascii::into_bytes(string);
    vector::append(&mut bytes, key);
    ascii::string(bytes)    
  }
}