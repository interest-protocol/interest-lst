// Sui Yield is a Wrapped SFA with extra information about the yield
// Reward paid is the rewards paid to date
// Principal was the original principal to create the yield
module interest_lsd::sui_yield {
  use std::ascii;
  use std::option;
  use std::string::String;

  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;

  use interest_lsd::math::{fdiv, fmul};
  use interest_lsd::admin::AdminCap;
  use interest_lsd::semi_fungible_asset::{Self as sfa, SFATreasuryCap, SemiFungibleAsset, SFAMetadata};
  
  // ** Only module that can mint/burn/create/mutate this SFA
  friend interest_lsd::pool;

  // OTW to create the Sui Yield
  struct SUI_YIELD has drop {}

  // ** Structs

  // SFA Data

  struct SuiYield has key, store {
    id: UID,
    sfa: SemiFungibleAsset<SUI_YIELD>,
    principal: u64,
    rewards_paid: u64
  }

  struct SuiYieldStorage has key {
    id: UID,
    treasury_cap: SFATreasuryCap<SUI_YIELD>
  }

  // ** Events

  fun init(witness: SUI_YIELD, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = sfa::create_sfa(
      witness,
      9,
      b"iSUIY",
      b"Interest Sui Yield",
      b"It represents the yield of Native Staked Sui in the Interest LSD pool.", 
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

  public fun value(asset: &SuiYield): u64 {
    sfa::value(&asset.sfa)
  }

  public fun slot(asset: &SuiYield): u256 {
    sfa::slot(&asset.sfa)
  }

  public fun join(
    self: &mut SuiYield,
    asset: SuiYield,     
    ) {
    let SuiYield { sfa: a, id, principal, rewards_paid } = asset;
    object::delete(id);
    sfa::join(&mut self.sfa, a);
    self.principal = self.principal + principal;
    self.rewards_paid = self.rewards_paid + rewards_paid;
  }

  public fun split(
    asset: &mut SuiYield,
    split_amount: u64,
    ctx: &mut TxContext     
  ): SuiYield {
    let v = (value(asset) as u256);
    let a = sfa::split(&mut asset.sfa, split_amount, ctx);
    // 1e18
    let split_percentage = fdiv((split_amount as u256), v);
    let split_principal = (fmul(split_percentage, (asset.principal as u256)) as u64);
    let split_rewards_paid = (fmul(split_percentage, (asset.rewards_paid as u256)) as u64);
    let x = SuiYield {
      id: object::new(ctx),
      sfa: a,
      principal: split_principal,
      rewards_paid: split_rewards_paid
    };

    asset.principal = asset.principal - split_principal;
    asset.rewards_paid = asset.rewards_paid - split_rewards_paid;
    x
  }

  public fun zero(storage: &mut SuiYieldStorage, slot: u256, ctx: &mut TxContext): SuiYield {
    SuiYield {
      id: object::new(ctx),
      sfa: sfa::zero(&mut storage.treasury_cap, slot, ctx),
      principal: 0, 
      rewards_paid: 0
    }
  }

  public fun read_principal(asset: &SuiYield): u64 {
    asset.principal
  }

  public fun read_reward_paid(asset: &SuiYield): u64 {
    asset.rewards_paid
  }

  public fun read_data(asset: &SuiYield): (u64, u64, u64) {
    (value(asset), asset.principal, asset.rewards_paid)
  }

  public fun is_zero(asset: &SuiYield): bool {
    sfa::is_zero(&asset.sfa)
  }

  public fun destroy_zero(asset: SuiYield) {
    let SuiYield {sfa: a, id, rewards_paid: _, principal: _} = asset;
    sfa::destroy_zero(a);
    object::delete(id);
  }

  public fun burn(storage: &mut SuiYieldStorage, asset: &mut SuiYield, value: u64) {
    sfa::burn(&mut storage.treasury_cap,&mut asset.sfa, value);
  } 

  public fun burn_destroy(storage: &mut SuiYieldStorage, asset: SuiYield): u64 {
    let value = value(&asset);
    burn(storage, &mut asset, value);
    destroy_zero(asset);
    value
  } 

  // === FRIEND ONLY Functions ===

  public(friend) fun new(
    storage: &mut SuiYieldStorage, 
    slot: u256, 
    value: u64, 
    principal: u64, 
    rewards_paid: u64, 
    ctx: &mut TxContext
  ): SuiYield {
    SuiYield {
      id: object::new(ctx),
      sfa: sfa::new(&mut storage.treasury_cap, slot, value, ctx),
      principal,
      rewards_paid 
    }
  } 

  public(friend) fun mint(storage: &mut SuiYieldStorage, asset: &mut SuiYield, value: u64) {
    sfa::mint(&mut storage.treasury_cap, &mut asset.sfa, value);
  }   

  public(friend) fun update_data(
    asset: &mut SuiYield,
    principal: u64, 
    rewards_paid: u64,     
    ) {
    asset.principal = principal;
    asset.rewards_paid = rewards_paid;
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