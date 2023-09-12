// Interest lst Staked Sui is a Semi-Fungible Coin  
// It represents an active deposit on the pool (NO YIELD - just the residue/principal)
module interest_lst::sui_principal {
  use std::ascii;
  use std::option;
  use std::string::String;

  use sui::url;
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;

  use interest_lst::admin::AdminCap;
  use interest_lst::semi_fungible_token::{Self as sft, SFTTreasuryCap, SemiFungibleToken, SFTMetadata};
  
  // ** Only module that can mint/burn/create/mutate this SFT
  friend interest_lst::pool;

  // OTW to create the Staked Sui
  struct SUI_PRINCIPAL has drop {}

  // ** Structs

  struct SuiPrincipalStorage has key {
    id: UID,
    treasury_cap: SFTTreasuryCap<SUI_PRINCIPAL>
  }

  fun init(witness: SUI_PRINCIPAL, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = sft::create_sft(
      witness,
      9,
      b"iSUIP",
      b"Interest Sui Principal",
      b"It represents the principal of Native Staked Sui in the Interest LST pool", 
      b"The slot is the maturity epoch of this token.",
      option::some(url::new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmVvGuZZVhe78ewrCJLucPySVPio1VZRVnHSZpw9bNZTbD")),
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
    sft::total_supply_in_slot(&storage.treasury_cap, slot)
  }

  public fun value(self: &SemiFungibleToken<SUI_PRINCIPAL>): u64 {
    sft::value(self)
  }

  public fun slot(self: &SemiFungibleToken<SUI_PRINCIPAL>): u256 {
    sft::slot(self)
  }

  public fun zero(storage: &mut SuiPrincipalStorage, slot: u256, ctx: &mut TxContext): SemiFungibleToken<SUI_PRINCIPAL> {
    sft::zero(&mut storage.treasury_cap, slot, ctx)
  }

  public fun is_zero(token: &SemiFungibleToken<SUI_PRINCIPAL>): bool {
    sft::is_zero(token)
  }

  public fun destroy_zero(token: SemiFungibleToken<SUI_PRINCIPAL>) {
    sft::destroy_zero(token)
  }

  public fun burn(storage: &mut SuiPrincipalStorage, token: &mut SemiFungibleToken<SUI_PRINCIPAL>, value: u64) {
    sft::burn(&mut storage.treasury_cap, token, value);
  }  

  public fun burn_destroy(storage: &mut SuiPrincipalStorage, token: SemiFungibleToken<SUI_PRINCIPAL>): u64 {
    let value = value(&token);
    burn(storage, &mut token, value);
    destroy_zero(token);
    value
  } 

  // === FRIEND ONLY Functions ===

  public(friend) fun new(
    storage: &mut SuiPrincipalStorage, 
    slot: u256, 
    value: u64, 
    ctx: &mut TxContext
  ): SemiFungibleToken<SUI_PRINCIPAL> {
    sft::new(&mut storage.treasury_cap, slot, value, ctx)
  } 

  public(friend) fun mint(storage: &mut SuiPrincipalStorage, token: &mut SemiFungibleToken<SUI_PRINCIPAL>, value: u64) {
    sft::mint(&mut storage.treasury_cap, token, value);
  }  

  // === ADMIN ONLY Functions ===

  public entry fun update_name(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFTMetadata<SUI_PRINCIPAL>, name: String
  ) { sft::update_name(&mut storage.treasury_cap, metadata, name); }

  public entry fun update_symbol(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFTMetadata<SUI_PRINCIPAL>, symbol: ascii::String
  ) { sft::update_symbol(&mut storage.treasury_cap, metadata, symbol) }

  public entry fun update_description(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFTMetadata<SUI_PRINCIPAL>, description: String
  ) { sft::update_description(&mut storage.treasury_cap, metadata, description) }

  public entry fun update_slot_description(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFTMetadata<SUI_PRINCIPAL>, slot_description: String
  ) { sft::update_slot_description(&mut storage.treasury_cap, metadata, slot_description) }

  public entry fun update_icon_url(
    _:&AdminCap, storage: &mut SuiPrincipalStorage, metadata: &mut SFTMetadata<SUI_PRINCIPAL>, url: ascii::String
  ) {
    sft::update_icon_url(&storage.treasury_cap, metadata, url);
  }


  // === TEST ONLY Functions ===

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SUI_PRINCIPAL {}, ctx);
  }

  #[test_only]
  public fun new_for_testing(
    storage: &mut SuiPrincipalStorage, 
    slot: u256, 
    value: u64, 
    ctx: &mut TxContext
  ): SemiFungibleToken<SUI_PRINCIPAL> {
    new(storage, slot, value, ctx)
  } 

  #[test_only]
  public fun mint_for_testing(storage: &mut SuiPrincipalStorage, token: &mut SemiFungibleToken<SUI_PRINCIPAL>, value: u64) {
    mint(storage, token, value);
  }  
}