// The LP Token of the Sui Bond AMM
module interest_lst::lp_token {
  use std::ascii;
  use std::option;
  use std::string::String;

  use sui::url;
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;

  use interest_lst::admin::AdminCap;
  use interest_lst::semi_fungible_token::{Self as sft, SemiFungibleToken as SFT, SFTTreasuryCap, SFTMetadata};

  friend interest_lst::amm;

  struct LP_TOKEN has drop {}
  
  struct LPTokenStorage has key {
    id: UID,
    treasury_cap: SFTTreasuryCap<LP_TOKEN>
  }

  fun init(witness: LP_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = sft::create_sft(
      witness,
      9,
      b"LP-iSUIP/iSUIY",
      b"Liquidity Provider Token for iSui/iSUIP pools",
      b"It represents a liquidity share of a iSui/iSUIP pool", 
      b"The slot is the maturity epoch of the liquidity.",
      option::some(url::new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmeJ92yFYeJEwCWFzAkRg1p1xxrmKJscAe5NtrTiKybdAT")),
      ctx      
    );
    
    transfer::share_object(LPTokenStorage { id: object::new(ctx), treasury_cap });
    transfer::public_share_object(metadata);
  }

  public(friend) fun mint(
    storage: &mut LPTokenStorage, 
    slot: u64,
    amount: u64, 
    ctx: &mut TxContext
  ): SFT<LP_TOKEN> {
    sft::mint(&mut storage.treasury_cap, (slot as u256), amount, ctx)
  }

  public fun burn(storage: &mut LPTokenStorage, token: SFT<LP_TOKEN>): u64 {
    sft::burn(&mut storage.treasury_cap, token)
  }

  // === ADMIN ONLY Functions ===

  public entry fun update_name(
    _:&AdminCap, storage: &mut LPTokenStorage, metadata: &mut SFTMetadata<LP_TOKEN>, name: String
  ) { sft::update_name(&mut storage.treasury_cap, metadata, name); }

  public entry fun update_symbol(
    _:&AdminCap, storage: &mut LPTokenStorage, metadata: &mut SFTMetadata<LP_TOKEN>, symbol: ascii::String
  ) { sft::update_symbol(&mut storage.treasury_cap, metadata, symbol) }

  public entry fun update_description(
    _:&AdminCap, storage: &mut LPTokenStorage, metadata: &mut SFTMetadata<LP_TOKEN>, description: String
  ) { sft::update_description(&mut storage.treasury_cap, metadata, description) }

  public entry fun update_slot_description(
    _:&AdminCap, storage: &mut LPTokenStorage, metadata: &mut SFTMetadata<LP_TOKEN>, slot_description: String
  ) { sft::update_slot_description(&mut storage.treasury_cap, metadata, slot_description) }

  public entry fun update_icon_url(
    _:&AdminCap, storage: &mut LPTokenStorage, metadata: &mut SFTMetadata<LP_TOKEN>, url: ascii::String
  ) {
    sft::update_icon_url(&storage.treasury_cap, metadata, url);
  }


  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(LP_TOKEN {}, ctx);
  }

  #[test_only]
   public fun mint_with_supply_for_testing(storage: &mut LPTokenStorage, slot: u64, value: u64 , ctx: &mut TxContext): SFT<LP_TOKEN> {
    mint(storage, slot, value, ctx)
  } 

  #[test_only]
  public fun mint_for_testing(
    slot: u64, 
    value: u64, 
    ctx: &mut TxContext
  ): SFT<LP_TOKEN> {
    sft:: mint_for_testing((slot as u256), value, ctx)
  } 

  #[test_only]
  public fun burn_for_testing(token: SFT<LP_TOKEN>): (u256, u64) {
    sft::burn_for_testing(token)
  }    
}