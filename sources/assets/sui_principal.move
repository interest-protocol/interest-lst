// Interest LSD Staked Sui is a Semi-Fungible Coin  
// It represents an active deposit on the pool (NO YIELD - just the residue/principal)
module interest_lsd::sui_principal {
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
  struct SUI_PRINCIPAL has drop {}

  // ** Structs

  struct SuiPrincipalStorage has key {
    id: UID,
    treasury_cap: SFATreasuryCap<SUI_PRINCIPAL>
  }

  fun init(witness: SUI_PRINCIPAL, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = sfa::create_sfa(
      witness,
      9,
      b"iSUIP",
      b"Interest Sui Principal",
      b"It represents the principal of Native Staked Sui in the Interest LSD pool", 
      b"The slot is the maturity epoch of this asset.",
      option::none(),
      ctx
    );

    transfer::share_object(
      SuiPrincipalStorage {
        id: object::new(ctx),
        treasury_cap
      }
    );
    transfer::public_share_object(metadata);
  }

  // === Open Functions ===

  public fun total_supply_in_slot(storage: &SuiPrincipalStorage, slot: u256): u64 {
    sfa::total_supply_in_slot(&storage.treasury_cap, slot)
  }

  public fun value(self: &SemiFungibleAsset<SUI_PRINCIPAL>): u64 {
    sfa::value(self)
  }

  public fun slot(self: &SemiFungibleAsset<SUI_PRINCIPAL>): u256 {
    sfa::slot(self)
  }

  public fun zero(storage: &mut SuiPrincipalStorage, slot: u256, ctx: &mut TxContext): SemiFungibleAsset<SUI_PRINCIPAL> {
    sfa::zero(&mut storage.treasury_cap, slot, ctx)
  }

  public fun is_zero(asset: &SemiFungibleAsset<SUI_PRINCIPAL>): bool {
    sfa::is_zero(asset)
  }

  public fun destroy_zero(asset: SemiFungibleAsset<SUI_PRINCIPAL>) {
    sfa::destroy_zero(asset)
  }

  public fun burn(storage: &mut SuiPrincipalStorage, asset: &mut SemiFungibleAsset<SUI_PRINCIPAL>, value: u64) {
    sfa::burn(&mut storage.treasury_cap, asset, value);
  }  

  public fun burn_destroy(storage: &mut SuiPrincipalStorage, asset: SemiFungibleAsset<SUI_PRINCIPAL>): u64 {
    let value = value(&asset);
    burn(storage, &mut asset, value);
    destroy_zero(asset);
    value
  } 

  // === FRIEND ONLY Functions ===

  public(friend) fun new(
    storage: &mut SuiPrincipalStorage, 
    slot: u256, 
    value: u64, 
    ctx: &mut TxContext
  ): SemiFungibleAsset<SUI_PRINCIPAL> {
    sfa::new(&mut storage.treasury_cap, slot, value, ctx)
  } 

  public(friend) fun mint(storage: &mut SuiPrincipalStorage, asset: &mut SemiFungibleAsset<SUI_PRINCIPAL>, value: u64) {
    sfa::mint(&mut storage.treasury_cap, asset, value);
  }  

  // === ADMIN ONLY Functions ===

  public entry fun update_name(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFAMetadata<SUI_PRINCIPAL>, name: String
  ) { sfa::update_name(&mut storage.treasury_cap, metadata, name); }

  public entry fun update_symbol(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFAMetadata<SUI_PRINCIPAL>, symbol: ascii::String
  ) { sfa::update_symbol(&mut storage.treasury_cap, metadata, symbol) }

  public entry fun update_description(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFAMetadata<SUI_PRINCIPAL>, description: String
  ) { sfa::update_description(&mut storage.treasury_cap, metadata, description) }

  public entry fun update_slot_description(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFAMetadata<SUI_PRINCIPAL>, slot_description: String
  ) { sfa::update_slot_description(&mut storage.treasury_cap, metadata, slot_description) }

  public entry fun update_icon_url(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFAMetadata<SUI_PRINCIPAL>, url: ascii::String
  ) {
    sfa::update_icon_url(&storage.treasury_cap, metadata, url);
  }


  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SUI_PRINCIPAL {}, ctx);
  }
}