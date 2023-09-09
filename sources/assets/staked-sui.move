// Interest LSD Staked Sui is a Semi-Fungible Coin  
// It represents an active deposit on the pool (NO YIELD - just the residue/principal)
module interest_lsd::staked_sui {
  use std::ascii;
  use std::option;
  use std::string::String;

  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;

  use interest_lsd::admin::AdminCap;
  use interest_lsd::semi_fungible_asset::{Self as sfa, SFATreasuryCap, SemiFungibleAsset, SFAMetadata};
  
  // ** Only module that can mint/burn/create/mutate this SFA
  friend interest_lsd::pool;

  // OTW to create the Staked Sui
  struct STAKED_SUI has drop {}

  // ** Structs

  struct StakedSuiStorage has key {
    id: UID,
    treasury_cap: SFATreasuryCap<STAKED_SUI>
  }

  fun init(witness: STAKED_SUI, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = sfa::create_sfa(
      witness,
      9,
      b"isSUI",
      b"Interest Staked Sui",
      b"It represents the principal of Native Staked Sui in the Interest LSD pool", 
      b"The slot is the maturity epoch of this asset.",
      option::none(),
      ctx
    );

    transfer::share_object(
      StakedSuiStorage {
        id: object::new(ctx),
        treasury_cap
      }
    );
    transfer::public_share_object(metadata);
  }

  // === Open Functions ===

  public fun total_supply_in_slot(storage: &StakedSuiStorage, slot: u256): u64 {
    sfa::total_supply_in_slot(&storage.treasury_cap, slot)
  }

  public fun value(self: &SemiFungibleAsset<STAKED_SUI>): u64 {
    sfa::value(self)
  }

  public fun slot(self: &SemiFungibleAsset<STAKED_SUI>): u256 {
    sfa::slot(self)
  }

  public fun zero(storage: &mut StakedSuiStorage, slot: u256, ctx: &mut TxContext): SemiFungibleAsset<STAKED_SUI> {
    sfa::zero(&mut storage.treasury_cap, slot, ctx)
  }

  public fun is_zero(asset: &SemiFungibleAsset<STAKED_SUI>): bool {
    sfa::is_zero(asset)
  }

  public fun destroy_zero(asset: SemiFungibleAsset<STAKED_SUI>) {
    sfa::destroy_zero(asset)
  }

  public fun burn(storage: &mut StakedSuiStorage, asset: &mut SemiFungibleAsset<STAKED_SUI>, value: u64) {
    sfa::burn(&mut storage.treasury_cap, asset, value);
  }  

  public fun burn_destroy(storage: &mut StakedSuiStorage, asset: SemiFungibleAsset<STAKED_SUI>): u64 {
    let value = value(&asset);
    burn(storage, &mut asset, value);
    destroy_zero(asset);
    value
  } 

  // === FRIEND ONLY Functions ===

  public(friend) fun new(
    storage: &mut StakedSuiStorage, 
    slot: u256, 
    value: u64, 
    ctx: &mut TxContext
  ): SemiFungibleAsset<STAKED_SUI> {
    sfa::new(&mut storage.treasury_cap, slot, value, ctx)
  } 

  public(friend) fun mint(storage: &mut StakedSuiStorage, asset: &mut SemiFungibleAsset<STAKED_SUI>, value: u64) {
    sfa::mint(&mut storage.treasury_cap, asset, value);
  }  

  // === ADMIN ONLY Functions ===

  public entry fun update_name(
    _:&AdminCap, storage: &mut StakedSuiStorage, metadata: &mut SFAMetadata<STAKED_SUI>, name: String
  ) { sfa::update_name(&mut storage.treasury_cap, metadata, name); }

  public entry fun update_symbol(
    _:&AdminCap, storage: &mut StakedSuiStorage, metadata: &mut SFAMetadata<STAKED_SUI>, symbol: ascii::String
  ) { sfa::update_symbol(&mut storage.treasury_cap, metadata, symbol) }

  public entry fun update_description(
    _:&AdminCap, storage: &mut StakedSuiStorage, metadata: &mut SFAMetadata<STAKED_SUI>, description: String
  ) { sfa::update_description(&mut storage.treasury_cap, metadata, description) }

  public entry fun update_slot_description(
    _:&AdminCap, storage: &mut StakedSuiStorage, metadata: &mut SFAMetadata<STAKED_SUI>, slot_description: String
  ) { sfa::update_slot_description(&mut storage.treasury_cap, metadata, slot_description) }

  public entry fun update_icon_url(
    _:&AdminCap, storage: &mut StakedSuiStorage, metadata: &mut SFAMetadata<STAKED_SUI>, url: ascii::String
  ) {
    sfa::update_icon_url(&storage.treasury_cap, metadata, url);
  }


  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(STAKED_SUI {}, ctx);
  }
}