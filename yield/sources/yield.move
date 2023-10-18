module yield::yield {
  use std::ascii;
  use std::option::Option;
  use std::string::String;

  use sui::url::Url;
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;

  use suitears::fixed_point_wad::{wad_mul_down as fmul, wad_div_down as fdiv};
  use suitears::semi_fungible_token::{Self as sft, SemiFungibleToken, SftTreasuryCap, SftMetadata};


  struct Yield<phantom OTW: drop> has key, store {
    id: UID,
    sft: SemiFungibleToken<OTW>,
    shares: u64,
    rewards_paid: u64
  }


  public fun create<OTW: drop>(    
    witness: OTW,
    decimals: u8,
    symbol: vector<u8>,
    name: vector<u8>,
    description: vector<u8>,
    slot_description: vector<u8>,
    icon_url: Option<Url>,
    ctx: &mut TxContext 
  ): (SftTreasuryCap<OTW>, SftMetadata<OTW>) {
    sft::create_sft(
      witness,
      decimals,
      symbol,
      name,
      description,
      slot_description,
      icon_url,
      ctx
    )
  }

  public fun total_supply<T: drop>(cap: &SftTreasuryCap<T>, slot: u256): u64 {
    sft::total_supply(cap, slot)
  }

  public fun value<T: drop>(asset: &Yield<T>): u64 {
    sft::value(&asset.sft)
  }

  public fun slot<T: drop>(asset: &Yield<T>): u256 {
    sft::slot(&asset.sft)
  }

  public fun join<T: drop>(
    self: &mut Yield<T>,
    asset: Yield<T>,     
    ) {
    let Yield { sft: a, id, shares, rewards_paid } = asset;
    object::delete(id);
    sft::join(&mut self.sft, a);
    self.shares = self.shares + shares;
    self.rewards_paid = self.rewards_paid + rewards_paid;
  }

  public fun split<T: drop>(
    asset: &mut Yield<T>,
    split_amount: u64,
    ctx: &mut TxContext     
  ): Yield<T> {
    let v = (value(asset) as u128);
    let a = sft::split(&mut asset.sft, split_amount, ctx);
    // 1e18
    let split_percentage = fdiv((split_amount as u128), v);
    let split_shares = (fmul(split_percentage, (asset.shares as u128)) as u64);
    let split_rewards_paid = (fmul(split_percentage, (asset.rewards_paid as u128)) as u64);
    let x = Yield {
      id: object::new(ctx),
      sft: a,
      shares: split_shares,
      rewards_paid: split_rewards_paid
    };

    asset.shares = asset.shares - split_shares;
    asset.rewards_paid = asset.rewards_paid - split_rewards_paid;
    x
  }

  public fun zero<T: drop>(slot: u256, ctx: &mut TxContext): Yield<T> {
    Yield {
      id: object::new(ctx),
      sft: sft::zero( slot, ctx),
      shares: 0, 
      rewards_paid: 0
    }
  }

  public fun shares<T: drop>(asset: &Yield<T>): u64 {
    asset.shares
  }

  public fun rewards_paid<T: drop>(asset: &Yield<T>): u64 {
    asset.rewards_paid
  }

  public fun read_data<T: drop>(asset: &Yield<T>): (u64, u64, u64) {
    (asset.shares, value(asset), asset.rewards_paid)
  }

  public fun is_zero<T: drop>(asset: &Yield<T>): bool {
    sft::is_zero(&asset.sft)
  }

  public fun burn_zero<T: drop>(asset: Yield<T>) {
    let Yield {sft: a, id, rewards_paid: _, shares: _} = asset;
    sft::burn_zero(a);
    object::delete(id);
  }

  public fun burn<T: drop>(cap: &mut SftTreasuryCap<T>, asset: Yield<T>): (u64, u64, u64) {
    let (x, y, z) = read_data(&asset);

    let Yield { id, sft, shares:_, rewards_paid:_} = asset;
    object::delete(id);
    sft::burn(cap, sft);
    (x, y, z)
  } 

  // === MINTER ONLY Functions ===

  public fun mint<T: drop>(
    cap: &mut SftTreasuryCap<T>, 
    slot: u256, 
    principal: u64, 
    shares: u64, 
    ctx: &mut TxContext
  ): Yield<T> {
    Yield {
      id: object::new(ctx),
      sft: sft::mint(cap, slot, principal, ctx),
      shares,
      rewards_paid: 0 
    }
  } 

  public fun add_rewards_paid<T: drop>(
    _: &SftTreasuryCap<T>, 
    asset: &mut Yield<T>,
    rewards_paid: u64,     
    ) {
    asset.rewards_paid = asset.rewards_paid + rewards_paid;
  }

  public fun set_shares<T: drop>(
    _: &SftTreasuryCap<T>,  
    asset: &mut Yield<T>,
    shares: u64,     
  ) {
    asset.shares = shares;
  }

  public fun set_rewards_paid<T: drop>(
    _: &SftTreasuryCap<T>,  
    asset: &mut Yield<T>,
    rewards_paid: u64,     
    ) {
    asset.rewards_paid =  rewards_paid;
  }

  public fun expire<T: drop>(cap: &mut SftTreasuryCap<T>, asset: Yield<T>, ctx: &mut TxContext): Yield<T> {
    let x = zero(slot(&asset),  ctx);
    burn(cap, asset);
    x
  }

  // === ADMIN ONLY Functions ===

  public entry fun update_name<T: drop>(
    cap: &mut SftTreasuryCap<T>, metadata: &mut SftMetadata<T>, name: String
  ) { sft::update_name(cap, metadata, name); }

  public entry fun update_symbol<T: drop>(
    cap: &mut SftTreasuryCap<T>, metadata: &mut SftMetadata<T>, symbol: ascii::String
  ) { sft::update_symbol(cap, metadata, symbol) }

  public entry fun update_description<T: drop>(
    cap: &mut SftTreasuryCap<T>, metadata: &mut SftMetadata<T>, description: String
  ) { sft::update_description(cap, metadata, description) }

  public entry fun update_slot_description<T: drop>(
    cap: &mut SftTreasuryCap<T>, metadata: &mut SftMetadata<T>, slot_description: String
  ) { sft::update_slot_description(cap, metadata, slot_description) }

  public entry fun update_icon_url<T: drop>(
    cap: &mut SftTreasuryCap<T>, metadata: &mut SftMetadata<T>, url: ascii::String
  ) {
    sft::update_icon_url(cap, metadata, url);
  }


  // === TEST ONLY Functions ===

  #[test_only]
  public fun mint_with_supply_for_testing<T: drop>(
    cap: &mut SftTreasuryCap<T>, 
    slot: u256, 
    principal: u64, 
    shares: u64, 
    ctx: &mut TxContext
  ): Yield {
      Yield {
      id: object::new(ctx),
      sft: sft::mint(cap, slot, principal, ctx),
      shares,
      rewards_paid: 0 
    }
  } 

  #[test_only]
  public fun mint_for_testing(
    slot: u256, 
    principal: u64, 
    shares: u64,
    rewards_paid: u64,
    ctx: &mut TxContext
  ): Yield {
    Yield {
      id: object::new(ctx),
      sft: sft::mint_for_testing( slot, principal, ctx),
      shares,
      rewards_paid
    }
  }  

  #[test_only]
  public fun burn_for_testing(asset: Yield): (u64, u64, u64) {
    let (x, y, z) = read_data(&asset);

    let Yield { id, sft, shares:_, rewards_paid:_} = asset;
    object::delete(id);
    sft::burn_for_testing(sft);
    (x, y, z)
  } 

  #[test_only]
  public fun add_rewards_paid_for_testing(
    asset: &mut Yield,
    rewards_paid: u64,     
    ) {
    asset.rewards_paid = asset.rewards_paid + rewards_paid;
  }

  #[test_only]
  public fun set_shares_for_testing(
    asset: &mut Yield,
    shares: u64,     
    ) {
    asset.shares = shares;
  }

  #[test_only]
  public fun set_rewards_paid_for_testing(
    asset: &mut Yield,
    rewards_paid: u64,     
    ) {
    asset.rewards_paid =  rewards_paid;
  }  
}