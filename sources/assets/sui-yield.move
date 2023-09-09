// Sui Yield is a Yield Bearing Fungible Asset  
// It accrues rewards from Interest LSD Pool
module interest_lsd::sui_yield {
  use std::ascii;
  use std::option;
  use std::string::{String};

  use sui::transfer;
  use sui::event::{emit};
  use sui::object::{Self, UID, ID};
  use sui::tx_context::{Self, TxContext};

  use interest_lsd::admin::{AdminCap};
  use interest_lsd::semi_fungible_asset_with_data::{Self as sfa, SFATreasuryCap, SemiFungibleAsset, SFAMetadata};
  
  // ** Only module that can mint/burn/create/mutate this SFA
  friend interest_lsd::pool;

  // OTW to create the Sui Yield
  struct SUI_YIELD has drop {}

  // ** Structs

  // SFA Data
  struct SuiYieldData has store, drop {
    principal: u64,
    rewards_paid: u64
  }

  struct SuiYieldStorage has key {
    id: UID,
    treasury_cap: SFATreasuryCap<SUI_YIELD>
  }

  // ** Events

  struct TransferValue has drop, copy {
    from_id: ID,
    to_id: ID,
    value: u64,
    sender: address,
    slot: u256
  }

  struct DestroySuiYield has drop, copy {
    asset_id: ID,
    slot: u256,
    sender: address
  }

  fun init(witness: SUI_YIELD, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = sfa::create_sfa(
      witness,
      9,
      b"SUIY",
      b"SuiYield",
      b"It represents the Yield portion of a Interest Sui position", 
      b"The slot is the maturity epoch of this asset",
      option::none(),
      ctx
    );

    transfer::share_object(
      SuiYieldStorage {
        id: object::new(ctx),
        treasury_cap
      }
    );
    transfer::public_share_object(metadata);
  }

  // === Open Functions ===

  public fun total_supply_in_slot(storage: &SuiYieldStorage, slot: u256): u64 {
    sfa::total_supply_in_slot(&storage.treasury_cap, slot)
  }

  public fun value(self: &SemiFungibleAsset<SUI_YIELD, SuiYieldData>): u64 {
    sfa::value(self)
  }

  public fun slot(self: &SemiFungibleAsset<SUI_YIELD, SuiYieldData>): u256 {
    sfa::slot(self)
  }

  public fun transfer_value(
    from: &mut SemiFungibleAsset<SUI_YIELD, SuiYieldData>, 
    to: &mut SemiFungibleAsset<SUI_YIELD, SuiYieldData>, 
    value: u64,
    ctx: &mut TxContext
  ) {
    sfa::transfer_value(from, to, value);
    emit(
      TransferValue {
        from_id: object::id(from),
        to_id: object::id(to),
        slot: sfa::slot(from),
        value,
        sender: tx_context::sender(ctx)
      }
    );
  }

  public fun zero(storage: &mut SuiYieldStorage, slot: u256, ctx: &mut TxContext): SemiFungibleAsset<SUI_YIELD, SuiYieldData> {
    sfa::zero(&mut storage.treasury_cap, slot, SuiYieldData { principal: 0, rewards_paid: 0}, ctx)
  }

  public fun read_data(asset: &SemiFungibleAsset<SUI_YIELD, SuiYieldData>): (u64, u64) {
    let data = sfa::borrow_data(asset);
    (data.principal, data.rewards_paid)
  }

  public fun is_zero(asset: &SemiFungibleAsset<SUI_YIELD, SuiYieldData>): bool {
    sfa::is_zero(asset)
  }

  public fun destroy_zero(asset: SemiFungibleAsset<SUI_YIELD, SuiYieldData>, ctx: &mut TxContext): (u256, u64) {
    emit(
      DestroySuiYield {
        asset_id: object::id(&asset),
        slot: slot(&asset),
        sender: tx_context::sender(ctx)
      }
    );
    sfa::destroy_zero(asset)
  }

  // === FRIEND ONLY Functions ===

  public(friend) fun new(
    storage: &mut SuiYieldStorage, 
    slot: u256, 
    value: u64, 
    principal: u64, 
    rewards_paid: u64, 
    ctx: &mut TxContext
  ): SemiFungibleAsset<SUI_YIELD,SuiYieldData> {
    sfa::new(&mut storage.treasury_cap, slot, value, SuiYieldData {principal, rewards_paid }, ctx)
  } 

  public(friend) fun mint(storage: &mut SuiYieldStorage, asset: &mut SemiFungibleAsset<SUI_YIELD, SuiYieldData>, value: u64) {
    sfa::mint(&mut storage.treasury_cap, asset, value);
  }  

  public(friend) fun burn(storage: &mut SuiYieldStorage, asset: &mut SemiFungibleAsset<SUI_YIELD, SuiYieldData>, value: u64) {
    sfa::burn(&mut storage.treasury_cap, asset, value);
  }  

  public(friend) fun update_data(
    asset: &mut SemiFungibleAsset<SUI_YIELD, SuiYieldData>,
    principal: u64, 
    rewards_paid: u64,     
    ) {
    let data = sfa::borrow_mut_data(asset);
    data.principal = principal;
    data.rewards_paid = rewards_paid;
  }

  // === ADMIN ONLY Functions ===

  public entry fun update_name(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFAMetadata<SUI_YIELD>, name: String
  ) { sfa::update_name(&mut storage.treasury_cap, metadata, name); }

  public entry fun update_symbol(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFAMetadata<SUI_YIELD>, symbol: ascii::String
  ) { sfa::update_symbol(&mut storage.treasury_cap, metadata, symbol) }

  public entry fun update_description(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFAMetadata<SUI_YIELD>, description: String
  ) { sfa::update_description(&mut storage.treasury_cap, metadata, description) }

  public entry fun update_slot_description(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFAMetadata<SUI_YIELD>, slot_description: String
  ) { sfa::update_slot_description(&mut storage.treasury_cap, metadata, slot_description) }

  public entry fun update_icon_url(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFAMetadata<SUI_YIELD>, url: ascii::String
  ) {
    sfa::update_icon_url(&storage.treasury_cap, metadata, url);
  }


  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SUI_YIELD {}, ctx);
  }
}