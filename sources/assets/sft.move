
/*
* Title - Semi Fungible Token
*
* Each TOken is fungible within the same slot and non-fungible accross slots
*/
module interest_lsd::semi_fungible_token {
  use std::ascii;
  use std::option::{Self, Option};
  use std::string::{String, utf8};

  use sui::url::{Self, Url};
  use sui::object::{Self, UID};
  use sui::table::{Self, Table};
  use sui::tx_context::TxContext;
  use sui::types::is_one_time_witness;

  // Errors
  const EIncompatibleSlots: u64 = 0;
  const EBadWitness: u64 = 1;
  const ETokenHasValue: u64 = 2;

  struct SemiFungibleToken<phantom T> has key, store {
    id: UID, // Makes it into an NFT
    slot: u256, // Provides fungibility between the NFTs
    value: u64, // Value the NFT holds
  }

  struct SFTMetadata<phantom T> has key, store {
    id: UID,
    decimals: u8,
    name: String,
    symbol: ascii::String,
    description: String,
    icon_url: Option<Url>,
    slot_description: String,
  }

  struct SFTTreasuryCap<phantom T> has key, store {
    id: UID,
    total_supply: Table<u256, u64>
  }

  public fun total_supply_in_slot<T>(cap: &SFTTreasuryCap<T>, slot: u256): u64 {
    *table::borrow(&cap.total_supply, slot)
  }

  public fun value<T>(self: &SemiFungibleToken<T>): u64 {
    self.value
  }

  public fun slot<T>(self: &SemiFungibleToken<T>): u256 {
    self.slot
  }
  
  public entry fun join<T>(self: &mut SemiFungibleToken<T>, a: SemiFungibleToken<T>) {
    let SemiFungibleToken { id, value, slot } = a;
    assert!(self.slot == slot, EIncompatibleSlots);
    object::delete(id);
    self.value = self.value + value
  }

  public fun split<T>(self: &mut SemiFungibleToken<T>, split_amount: u64, ctx: &mut TxContext): SemiFungibleToken<T> {
    // This will throw if it underflows
    self.value = self.value - split_amount;
    SemiFungibleToken {
      id: object::new(ctx),
      value: split_amount,
      slot: self.slot
    }
  }

  public fun zero<T>(cap: &mut SFTTreasuryCap<T>, slot: u256, ctx: &mut TxContext): SemiFungibleToken<T> {
    new_slot(cap, slot);
    
    SemiFungibleToken {
      id: object::new(ctx),
      slot,
      value: 0
    }
  }

  public fun create_sft<T: drop>(
    witness: T,
    decimals: u8,
    symbol: vector<u8>,
    name: vector<u8>,
    description: vector<u8>,
    slot_description: vector<u8>,
    icon_url: Option<Url>,
    ctx: &mut TxContext 
  ): (SFTTreasuryCap<T>, SFTMetadata<T>) {
    assert!(is_one_time_witness(&witness), EBadWitness);
    
    (
      SFTTreasuryCap {
        id: object::new(ctx),
        total_supply: table::new(ctx)
      },  
      SFTMetadata
        {
          id: object::new(ctx),
          decimals,
          name: utf8(name),
          symbol: ascii::string(symbol),
          description: utf8(description),
          slot_description: utf8(slot_description),
          icon_url
        }
    )    
  }

  public fun new<T>(cap: &mut SFTTreasuryCap<T>, slot: u256, value: u64, ctx: &mut TxContext): SemiFungibleToken<T> {
    new_slot(cap, slot);

    let supply = table::borrow_mut(&mut cap.total_supply, slot);
    *supply = *supply + value;

    SemiFungibleToken {
      id: object::new(ctx),
      value,
      slot
    }
  } 

  public fun mint<T>(cap: &mut SFTTreasuryCap<T>, token: &mut SemiFungibleToken<T>, value: u64) {
    let supply = table::borrow_mut(&mut cap.total_supply, token.slot);
    *supply = *supply + value;
    token.value = token.value + value;
  }

  public fun burn<T>(cap: &mut SFTTreasuryCap<T>, token: &mut SemiFungibleToken<T>, value: u64) {
    let supply = table::borrow_mut(&mut cap.total_supply, token.slot);
    *supply = *supply - value;
    token.value = token.value - value;
  }

  public fun is_zero<T>(token: &SemiFungibleToken<T>): bool {
    token.value == 0
  }

  public fun destroy_zero<T>(token: SemiFungibleToken<T>) {
    let SemiFungibleToken { id, slot: _ , value  } = token;
    assert!(value == 0, ETokenHasValue);
    object::delete(id);
  }

  // === Update Token SFTMetadata ===

    public entry fun update_name<T>(
        _: &SFTTreasuryCap<T>, metadata: &mut SFTMetadata<T>, name: String
    ) {
        metadata.name = name;
    }

    public entry fun update_symbol<T>(
        _: &SFTTreasuryCap<T>, metadata: &mut SFTMetadata<T>, symbol: ascii::String
    ) {
        metadata.symbol = symbol;
    }

    public entry fun update_description<T>(
        _: &SFTTreasuryCap<T>, metadata: &mut SFTMetadata<T>, description: String
    ) {
        metadata.description = description;
    }

    public entry fun update_slot_description<T>(
        _: &SFTTreasuryCap<T>, metadata: &mut SFTMetadata<T>, slot_description: String
    ) {
        metadata.slot_description = slot_description;
    }

    public entry fun update_icon_url<T>(
        _: &SFTTreasuryCap<T>, metadata: &mut SFTMetadata<T>, url: ascii::String
    ) {
        metadata.icon_url = option::some(url::new_unsafe(url));
    }

    // === Get Token metadata fields for on-chain consumption ===

    public fun get_decimals<T>(
        metadata: &SFTMetadata<T>
    ): u8 {
        metadata.decimals
    }

    public fun get_name<T>(
        metadata: &SFTMetadata<T>
    ): String {
        metadata.name
    }

    public fun get_symbol<T>(
        metadata: &SFTMetadata<T>
    ): ascii::String {
        metadata.symbol
    }

    public fun get_description<T>(
        metadata: &SFTMetadata<T>
    ): String {
        metadata.description
    }

    public fun get_slot_description<T>(
        metadata: &SFTMetadata<T>
    ): String {
        metadata.slot_description
    }

    public fun get_icon_url<T>(
        metadata: &SFTMetadata<T>
    ): Option<Url> {
        metadata.icon_url
    }

  fun new_slot<T>(cap: &mut SFTTreasuryCap<T>, slot: u256) {
    if (table::contains(&cap.total_supply, slot)) return;

    table::add(&mut cap.total_supply, slot, 0);
  }  

  // === Test-only code ===

  #[test_only]
  public fun create_for_testing<T>(slot: u256, value: u64, ctx: &mut TxContext): SemiFungibleToken<T> {
    SemiFungibleToken { id: object::new(ctx), slot, value }
  }

  #[test_only]
  public fun destroy_for_testing<T>(token: SemiFungibleToken<T>): (u256, u64) {
    let SemiFungibleToken { id, value, slot } = token;
    object::delete(id);
    (slot, value)
  }

  #[test_only]
  public fun mint_for_testing<T>(token: &mut SemiFungibleToken<T>, value: u64) {
    token.value = token.value + value;
  }

  #[test_only]
  public fun burn_for_testing<T>(token: &mut SemiFungibleToken<T>, value: u64) {
    token.value = token.value -  value;
  }
}