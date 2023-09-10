
/*
* Title - Semi Fungible Asset
*
* Each Asset is fungible within the same slot and non-fungible accross slots
*/
module interest_lsd::semi_fungible_asset {
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
  const EAssetHasValue: u64 = 2;

  struct SemiFungibleAsset<phantom T> has key, store {
    id: UID, // Makes it into an NFT
    slot: u256, // Provides fungibility between the NFTs
    value: u64, // Value the NFT holds
  }

  struct SFAMetadata<phantom T> has key, store {
    id: UID,
    decimals: u8,
    name: String,
    symbol: ascii::String,
    description: String,
    icon_url: Option<Url>,
    slot_description: String,
  }

  struct SFATreasuryCap<phantom T> has key, store {
    id: UID,
    total_supply: Table<u256, u64>
  }

  public fun total_supply_in_slot<T>(cap: &SFATreasuryCap<T>, slot: u256): u64 {
    *table::borrow(&cap.total_supply, slot)
  }

  public fun value<T>(self: &SemiFungibleAsset<T>): u64 {
    self.value
  }

  public fun slot<T>(self: &SemiFungibleAsset<T>): u256 {
    self.slot
  }
  
  public entry fun join<T>(self: &mut SemiFungibleAsset<T>, a: SemiFungibleAsset<T>) {
    let SemiFungibleAsset { id, value, slot } = a;
    assert!(self.slot == slot, EIncompatibleSlots);
    object::delete(id);
    self.value = self.value + value
  }

  public fun split<T>(self: &mut SemiFungibleAsset<T>, split_amount: u64, ctx: &mut TxContext): SemiFungibleAsset<T> {
    // This will throw if it underflows
    self.value = self.value - split_amount;
    SemiFungibleAsset {
      id: object::new(ctx),
      value: split_amount,
      slot: self.slot
    }
  }

  public fun zero<T>(cap: &mut SFATreasuryCap<T>, slot: u256, ctx: &mut TxContext): SemiFungibleAsset<T> {
    new_slot(cap, slot);
    
    SemiFungibleAsset {
      id: object::new(ctx),
      slot,
      value: 0
    }
  }

  public fun create_sfa<T: drop>(
    witness: T,
    decimals: u8,
    symbol: vector<u8>,
    name: vector<u8>,
    description: vector<u8>,
    slot_description: vector<u8>,
    icon_url: Option<Url>,
    ctx: &mut TxContext 
  ): (SFATreasuryCap<T>, SFAMetadata<T>) {
    assert!(is_one_time_witness(&witness), EBadWitness);
    
    (
      SFATreasuryCap {
        id: object::new(ctx),
        total_supply: table::new(ctx)
      },  
      SFAMetadata
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

  public fun new<T>(cap: &mut SFATreasuryCap<T>, slot: u256, value: u64, ctx: &mut TxContext): SemiFungibleAsset<T> {
    new_slot(cap, slot);

    let supply = table::borrow_mut(&mut cap.total_supply, slot);
    *supply = *supply + value;

    SemiFungibleAsset {
      id: object::new(ctx),
      value,
      slot
    }
  } 

  public fun mint<T>(cap: &mut SFATreasuryCap<T>, asset: &mut SemiFungibleAsset<T>, value: u64) {
    let supply = table::borrow_mut(&mut cap.total_supply, asset.slot);
    *supply = *supply + value;
    asset.value = asset.value + value;
  }

  public fun burn<T>(cap: &mut SFATreasuryCap<T>, asset: &mut SemiFungibleAsset<T>, value: u64) {
    let supply = table::borrow_mut(&mut cap.total_supply, asset.slot);
    *supply = *supply - value;
    asset.value = asset.value - value;
  }

  public fun is_zero<T>(asset: &SemiFungibleAsset<T>): bool {
    asset.value == 0
  }

  public fun destroy_zero<T>(asset: SemiFungibleAsset<T>) {
    let SemiFungibleAsset { id, slot: _ , value  } = asset;
    assert!(value == 0, EAssetHasValue);
    object::delete(id);
  }

  // === Update Asset SFAMetadata ===

    public entry fun update_name<T>(
        _: &SFATreasuryCap<T>, metadata: &mut SFAMetadata<T>, name: String
    ) {
        metadata.name = name;
    }

    public entry fun update_symbol<T>(
        _: &SFATreasuryCap<T>, metadata: &mut SFAMetadata<T>, symbol: ascii::String
    ) {
        metadata.symbol = symbol;
    }

    public entry fun update_description<T>(
        _: &SFATreasuryCap<T>, metadata: &mut SFAMetadata<T>, description: String
    ) {
        metadata.description = description;
    }

    public entry fun update_slot_description<T>(
        _: &SFATreasuryCap<T>, metadata: &mut SFAMetadata<T>, slot_description: String
    ) {
        metadata.slot_description = slot_description;
    }

    public entry fun update_icon_url<T>(
        _: &SFATreasuryCap<T>, metadata: &mut SFAMetadata<T>, url: ascii::String
    ) {
        metadata.icon_url = option::some(url::new_unsafe(url));
    }

    // === Get Asset metadata fields for on-chain consumption ===

    public fun get_decimals<T>(
        metadata: &SFAMetadata<T>
    ): u8 {
        metadata.decimals
    }

    public fun get_name<T>(
        metadata: &SFAMetadata<T>
    ): String {
        metadata.name
    }

    public fun get_symbol<T>(
        metadata: &SFAMetadata<T>
    ): ascii::String {
        metadata.symbol
    }

    public fun get_description<T>(
        metadata: &SFAMetadata<T>
    ): String {
        metadata.description
    }

    public fun get_slot_description<T>(
        metadata: &SFAMetadata<T>
    ): String {
        metadata.slot_description
    }

    public fun get_icon_url<T>(
        metadata: &SFAMetadata<T>
    ): Option<Url> {
        metadata.icon_url
    }

  fun new_slot<T>(cap: &mut SFATreasuryCap<T>, slot: u256) {
    if (table::contains(&cap.total_supply, slot)) return;

    table::add(&mut cap.total_supply, slot, 0);
  }  

  // === Test-only code ===

  #[test_only]
  public fun create_for_testing<T>(slot: u256, value: u64, ctx: &mut TxContext): SemiFungibleAsset<T> {
    SemiFungibleAsset { id: object::new(ctx), slot, value }
  }

  #[test_only]
  public fun destroy_for_testing<T>(asset: SemiFungibleAsset<T>): (u256, u64) {
    let SemiFungibleAsset { id, value, slot } = asset;
    object::delete(id);
    (slot, value)
  }

  #[test_only]
  public fun mint_for_testing<T>(asset: &mut SemiFungibleAsset<T>, value: u64) {
    asset.value = asset.value + value;
  }

  #[test_only]
  public fun burn_for_testing<T>(asset: &mut SemiFungibleAsset<T>, value: u64) {
    asset.value = asset.value -  value;
  }
}