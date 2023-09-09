
/*
* Title - Semi Fungible Asset
*
* Each Asset is fungible within the same slot and non-fungible accross slots
* Users can transfer value within assets with the same slot
* It has a data field for expressability and functionality
*/
module interest_lsd::semi_fungible_asset {
  use std::ascii;
  use std::string::{String, utf8};
  use std::option::{Self, Option};

  use sui::url::{Self, Url};
  use sui::object::{Self, UID};
  use sui::table::{Self, Table};
  use sui::tx_context::TxContext;
  use sui::vec_set::{Self, VecSet};
  use sui::types::is_one_time_witness;

  // Errors
  const EIncompatibleSlots: u64 = 0;
  const EBadWitness: u64 = 1;
  const EAssetHasValue: u64 = 2;

  struct SemiFungibleAsset<phantom T, D: store + drop> has key, store {
    id: UID, // Makes it into an NFT
    slot: u256, // Provides fungibility between the NFTs
    value: u64, // Value the NFT holds
    data: D
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
    total_supply: Table<u256, u64>,
    slots: VecSet<u256>
  }

  public fun total_supply_in_slot<T>(cap: &SFATreasuryCap<T>, slot: u256): u64 {
    *table::borrow(&cap.total_supply, slot)
  }

  public fun value<T, D: store + drop>(self: &SemiFungibleAsset<T, D>): u64 {
    self.value
  }

  public fun slot<T, D: store + drop>(self: &SemiFungibleAsset<T, D>): u256 {
    self.slot
  }

  public fun transfer_value<T, D: store + drop>(from: &mut SemiFungibleAsset<T, D>, to: &mut SemiFungibleAsset<T, D>, value: u64) {
    assert!(from.slot == to.slot, EIncompatibleSlots);
    from.value = from.value - value;
    to.value = to.value + value;
  }

  public fun zero<T, D: store + drop>(cap: &mut SFATreasuryCap<T>, slot: u256, data: D, ctx: &mut TxContext): SemiFungibleAsset<T, D> {
    if (!vec_set::contains(&cap.slots, &slot)) vec_set::insert(&mut cap.slots, slot);
    SemiFungibleAsset {
      id: object::new(ctx),
      slot,
      value: 0,
      data
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
        total_supply: table::new(ctx),
        slots: vec_set::empty()
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

  public fun new<T, D: store + drop>(cap: &mut SFATreasuryCap<T>, slot: u256, value: u64, data: D, ctx: &mut TxContext): SemiFungibleAsset<T, D> {
    if (!vec_set::contains(&cap.slots, &slot)) vec_set::insert(&mut cap.slots, slot);

    let supply = table::borrow_mut(&mut cap.total_supply, slot);
    *supply = *supply + value;

    SemiFungibleAsset {
      id: object::new(ctx),
      value,
      slot,
      data
    }
  } 

  public fun mint<T, D: store + drop>(cap: &mut SFATreasuryCap<T>, asset: &mut SemiFungibleAsset<T, D>, value: u64) {
    let supply = table::borrow_mut(&mut cap.total_supply, asset.slot);
    *supply = *supply + value;
    asset.value = asset.value + value;
  }

  public fun burn<T, D: store + drop>(cap: &mut SFATreasuryCap<T>, asset: &mut SemiFungibleAsset<T, D>, value: u64) {
    let supply = table::borrow_mut(&mut cap.total_supply, asset.slot);
    *supply = *supply - value;
    asset.value = asset.value - value;
  }

  public fun borrow_data<T, D: store + drop>(asset: &SemiFungibleAsset<T, D>): &D {
    &asset.data
  }

  public fun borrow_mut_data<T, D: store + drop>(asset: &mut SemiFungibleAsset<T, D>): &mut D {
    &mut asset.data
  }

  public fun is_zero<T, D: store + drop>(asset: &SemiFungibleAsset<T, D>): bool {
    asset.value == 0
  }

  public fun destroy_zero<T, D: store + drop>(asset: SemiFungibleAsset<T, D>): (u256, u64) {
    let SemiFungibleAsset { id, data: _, slot , value  } = asset;
    assert!(value == 0, EAssetHasValue);
    object::delete(id);
    (slot, value)
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

  // === Test-only code ===

  #[test_only]
  public fun create_for_testing<T, D: store + drop>(slot: u256, value: u64, data: D, ctx: &mut TxContext): SemiFungibleAsset<T, D> {
    SemiFungibleAsset { id: object::new(ctx), slot, value, data }
  }

  #[test_only]
  public fun destroy_for_testing<T, D: store + drop>(asset: SemiFungibleAsset<T, D>): (u256, u64) {
    let SemiFungibleAsset { id, value, slot, data: _ } = asset;
    object::delete(id);
    (slot, value)
  }

  #[test_only]
  public fun mint_for_testing<T, D: store + drop>(asset: &mut SemiFungibleAsset<T, D>, value: u64) {
    asset.value = asset.value + value;
  }

  #[test_only]
  public fun burn_for_testing<T, D: store + drop>(asset: &mut SemiFungibleAsset<T, D>, value: u64) {
    asset.value = asset.value -  value;
  }
}