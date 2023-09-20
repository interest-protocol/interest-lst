// Sui Yield is a Wrapped SFT with extra information about the yield
// Reward paid is the rewards paid to date
// Principal was the original shares to create the yield
module interest_lst::sui_yield {
  use std::ascii;
  use std::option;
  use std::string::String;

  use sui::url;
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;

  use interest_lst::math::{fdiv, fmul};
  use interest_lst::admin::AdminCap;
  use interest_lst::semi_fungible_token::{Self as sft, SFTTreasuryCap, SemiFungibleToken, SFTMetadata};
  
  // ** Only module that can mint/burn/create/mutate this SFT
  friend interest_lst::pool;

  // OTW to create the Sui Yield
  struct SUI_YIELD has drop {}

  // ** Structs

  // SFT Data

  struct SuiYield has key, store {
    id: UID,
    sft: SemiFungibleToken<SUI_YIELD>,
    shares: u64,
    rewards_paid: u64
  }

  struct SuiYieldStorage has key {
    id: UID,
    treasury_cap: SFTTreasuryCap<SUI_YIELD>
  }

  // ** Events

  fun init(witness: SUI_YIELD, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = sft::create_sft(
      witness,
      9,
      b"iSUIY",
      b"Interest Sui Yield",
      b"It represents the yield of Native Staked Sui in the Interest LST pool.", 
      b"The slot is the maturity epoch of this token",
      option::some(url::new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmWiC7W6gF5F7LeSKkAGwgcC58DmRb8BC254iA5N3QKSRz")),
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
    sft::total_supply_in_slot(&storage.treasury_cap, slot)
  }

  public fun value(token: &SuiYield): u64 {
    sft::value(&token.sft)
  }

  public fun slot(token: &SuiYield): u256 {
    sft::slot(&token.sft)
  }

  public fun join(
    self: &mut SuiYield,
    token: SuiYield,     
    ) {
    let SuiYield { sft: a, id, shares, rewards_paid } = token;
    object::delete(id);
    sft::join(&mut self.sft, a);
    self.shares = self.shares + shares;
    self.rewards_paid = self.rewards_paid + rewards_paid;
  }

  public fun split(
    token: &mut SuiYield,
    split_amount: u64,
    ctx: &mut TxContext     
  ): SuiYield {
    let v = (value(token) as u256);
    let a = sft::split(&mut token.sft, split_amount, ctx);
    // 1e18
    let split_percentage = fdiv((split_amount as u256), v);
    let split_shares = (fmul(split_percentage, (token.shares as u256)) as u64);
    let split_rewards_paid = (fmul(split_percentage, (token.rewards_paid as u256)) as u64);
    let x = SuiYield {
      id: object::new(ctx),
      sft: a,
      shares: split_shares,
      rewards_paid: split_rewards_paid
    };

    token.shares = token.shares - split_shares;
    token.rewards_paid = token.rewards_paid - split_rewards_paid;
    x
  }

  public fun zero(storage: &mut SuiYieldStorage, slot: u256, ctx: &mut TxContext): SuiYield {
    SuiYield {
      id: object::new(ctx),
      sft: sft::zero(&mut storage.treasury_cap, slot, ctx),
      shares: 0, 
      rewards_paid: 0
    }
  }

  public fun shares(token: &SuiYield): u64 {
    token.shares
  }

  public fun rewards_paid(token: &SuiYield): u64 {
    token.rewards_paid
  }

  public fun read_data(token: &SuiYield): (u64, u64, u64) {
    (token.shares, value(token), token.rewards_paid)
  }

  public fun is_zero(token: &SuiYield): bool {
    sft::is_zero(&token.sft)
  }

  public fun destroy_zero(token: SuiYield) {
    let SuiYield {sft: a, id, rewards_paid: _, shares: _} = token;
    sft::destroy_zero(a);
    object::delete(id);
  }

  public fun burn(storage: &mut SuiYieldStorage, token: &mut SuiYield, value: u64) {
    sft::burn(&mut storage.treasury_cap,&mut token.sft, value);
  } 

  public fun burn_destroy(storage: &mut SuiYieldStorage, token: SuiYield): u64 {
    let value = value(&token);
    burn(storage, &mut token, value);
    destroy_zero(token);
    value
  } 

  // === FRIEND ONLY Functions ===

  public(friend) fun new(
    storage: &mut SuiYieldStorage, 
    slot: u256, 
    principal: u64, 
    shares: u64, 
    ctx: &mut TxContext
  ): SuiYield {
    SuiYield {
      id: object::new(ctx),
      sft: sft::new(&mut storage.treasury_cap, slot, principal, ctx),
      shares,
      rewards_paid: 0 
    }
  } 

  public(friend) fun mint(storage: &mut SuiYieldStorage, token: &mut SuiYield, value: u64) {
    sft::mint(&mut storage.treasury_cap, &mut token.sft, value);
  }   

  public(friend) fun add_rewards_paid(
    token: &mut SuiYield,
    rewards_paid: u64,     
    ) {
    token.rewards_paid = token.rewards_paid + rewards_paid;
  }

  public(friend) fun set_shares(
    token: &mut SuiYield,
    shares: u64,     
    ) {
    token.shares = shares;
  }

  public(friend) fun set_rewards_paid(
    token: &mut SuiYield,
    rewards_paid: u64,     
    ) {
    token.rewards_paid =  rewards_paid;
  }

  public(friend) fun expire(storage: &mut SuiYieldStorage, token: &mut SuiYield) {
    token.rewards_paid = 0;
    token.shares = 0;
    let burn_value = value(token);
    burn(storage, token, burn_value);
  }

  // === ADMIN ONLY Functions ===

  public entry fun update_name(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFTMetadata<SUI_YIELD>, name: String
  ) { sft::update_name(&mut storage.treasury_cap, metadata, name); }

  public entry fun update_symbol(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFTMetadata<SUI_YIELD>, symbol: ascii::String
  ) { sft::update_symbol(&mut storage.treasury_cap, metadata, symbol) }

  public entry fun update_description(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFTMetadata<SUI_YIELD>, description: String
  ) { sft::update_description(&mut storage.treasury_cap, metadata, description) }

  public entry fun update_slot_description(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFTMetadata<SUI_YIELD>, slot_description: String
  ) { sft::update_slot_description(&mut storage.treasury_cap, metadata, slot_description) }

  public entry fun update_icon_url(
    _:&AdminCap, storage: &mut SuiYieldStorage, metadata: &mut SFTMetadata<SUI_YIELD>, url: ascii::String
  ) {
    sft::update_icon_url(&storage.treasury_cap, metadata, url);
  }


  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SUI_YIELD {}, ctx);
  }

  #[test_only]
  public fun new_for_testing(
    storage: &mut SuiYieldStorage, 
    slot: u256, 
    principal: u64, 
    shares: u64,
    rewards_paid: u64,
    ctx: &mut TxContext
  ): SuiYield {
    SuiYield {
      id: object::new(ctx),
      sft: sft::new(&mut storage.treasury_cap, slot, principal, ctx),
      shares,
      rewards_paid
    }
  } 

  #[test_only]
  public fun mint_for_testing(storage: &mut SuiYieldStorage, token: &mut SuiYield, value: u64) {
    mint(storage, token, value);
  }   

  #[test_only]
  public fun add_rewards_paid_for_testing(
    token: &mut SuiYield,
    rewards_paid: u64,     
    ) {
    token.rewards_paid = token.rewards_paid + rewards_paid;
  }

  #[test_only]
  public fun set_shares_for_testing(
    token: &mut SuiYield,
    shares: u64,     
    ) {
    token.shares = shares;
  }

  #[test_only]
  public fun set_rewards_paid_for_testing(
    token: &mut SuiYield,
    rewards_paid: u64,     
    ) {
    token.rewards_paid =  rewards_paid;
  }
}