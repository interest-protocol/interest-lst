// Interest lst Staked Sui is a Semi-Fungible Coin  
// It represents an active deposit on the pool (NO YIELD - just the residue/principal)
module interest_tokens::sui_principal {
  use std::ascii;
  use std::option;
  use std::string::String;

  use sui::url;
  use sui::transfer;
  use sui::event::emit;
  use sui::package::Publisher;
  use sui::object::{Self, UID, ID};
  use sui::vec_set::{Self, VecSet};
  use sui::tx_context::TxContext;

  use access::admin::AdminCap;
  
  use interest_framework::semi_fungible_token::{Self as sft, SFTTreasuryCap, SemiFungibleToken, SFTMetadata};

  // Errors
  const EInvalidMinter: u64 = 0;

  // OTW to create the Staked Sui
  struct SUI_PRINCIPAL has drop {}

  // ** Structs

  struct SuiPrincipalStorage has key {
    id: UID,
    treasury_cap: SFTTreasuryCap<SUI_PRINCIPAL>,
    minters: VecSet<ID> 
  }

  // ** Events

  struct MinterAdded has copy, drop {
    id: ID
  }

  struct MinterRemoved has copy, drop {
    id: ID
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
        treasury_cap,
        minters: vec_set::empty()
      }
    );
    transfer::public_share_object(metadata);
  }

  // === Open Functions ===

  public fun total_supply(storage: &SuiPrincipalStorage, slot: u256): u64 {
    sft::total_supply(&storage.treasury_cap, slot)
  }

  public fun value(self: &SemiFungibleToken<SUI_PRINCIPAL>): u64 {
    sft::value(self)
  }

  public fun slot(self: &SemiFungibleToken<SUI_PRINCIPAL>): u256 {
    sft::slot(self)
  }

  public fun zero(slot: u256, ctx: &mut TxContext): SemiFungibleToken<SUI_PRINCIPAL> {
    sft::zero( slot, ctx)
  }

  public fun is_zero(token: &SemiFungibleToken<SUI_PRINCIPAL>): bool {
    sft::is_zero(token)
  }

  public fun burn_zero(token: SemiFungibleToken<SUI_PRINCIPAL>) {
    sft::burn_zero(token)
  }

  public fun burn(storage: &mut SuiPrincipalStorage, token: SemiFungibleToken<SUI_PRINCIPAL>): u64 {
    sft::burn(&mut storage.treasury_cap, token)
  }  

  // === FRIEND ONLY Functions ===

  public fun mint(storage: &mut SuiPrincipalStorage, publisher: &Publisher, slot: u256, value: u64 , ctx: &mut TxContext): SemiFungibleToken<SUI_PRINCIPAL> {
    assert!(is_minter(storage, object::id(publisher)), EInvalidMinter);
    sft::mint(&mut storage.treasury_cap, slot, value, ctx)
  }  

  // === Minter Functions ===

  entry public fun add_minter(_: &AdminCap, storage: &mut SuiPrincipalStorage, id: ID) {
    vec_set::insert(&mut storage.minters, id);
    emit(
      MinterAdded {
        id
      }
    );
  }

  entry public fun remove_minter(_: &AdminCap, storage: &mut SuiPrincipalStorage, id: ID) {
    vec_set::remove(&mut storage.minters, &id);
    emit(
      MinterRemoved {
        id
      }
    );
  } 

  public fun is_minter(storage: &SuiPrincipalStorage, id: ID): bool {
    vec_set::contains(&storage.minters, &id)
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
   public fun mint_with_supply_for_testing(storage: &mut SuiPrincipalStorage, slot: u256, value: u64 , ctx: &mut TxContext): SemiFungibleToken<SUI_PRINCIPAL> {
    sft::mint(&mut storage.treasury_cap, slot, value, ctx)
  } 

  #[test_only]
  public fun mint_for_testing(
    slot: u256, 
    value: u64, 
    ctx: &mut TxContext
  ): SemiFungibleToken<SUI_PRINCIPAL> {
    sft:: mint_for_testing(slot, value, ctx)
  } 

  #[test_only]
  public fun burn_for_testing(token: SemiFungibleToken<SUI_PRINCIPAL>): (u256, u64) {
    sft::burn_for_testing(token)
  }  
}