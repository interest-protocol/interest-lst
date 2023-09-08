// Sui Yield is a Yield Bearing Fungible Asset  
// It accrues rewards from Interest LSD Pool
module interest_lsd::sui_yield {
  use std::string::{utf8, String};

  use sui::package;
  use sui::transfer;
  use sui::event::{emit};
  use sui::object::{Self, UID, ID};
  use sui::display::{Self, Display};
  use sui::tx_context::{Self, TxContext};

  use interest_lsd::admin::{AdminCap};
  
  // ** Only module that can mint/burn this NFT
  friend interest_lsd::pool;

  // ** Structs

  // NFT
  struct SuiYield has key, store {
    id: UID,
    principal: u64,
    shares: u64,
    /// ** Clean Mechanism. When is_clean is false, this NFT might have a rewards saved in a dynamic field. It is a UX mechanism to instruct developers to verify with the user if they want to first check their rewards before burning/joining/splitting. It is not enforced in any way.
    is_clean: bool
  }

  // OTW to create the Sui Yield
  struct SUI_YIELD has drop {}

  // Display Wrapper
  struct SuiYieldStorage has key {
    id: UID,
    display: Display<SuiYield>
  }

  // ** Events

  struct Mint has copy, drop {
    nft_id: ID,
    shares: u64,
    principal: u64,
    sender: address
  }

  struct Burn has copy, drop {
    nft_id: ID,
    shares: u64,
    principal: u64,
    sender: address
  }

  fun init(witness: SUI_YIELD, ctx: &mut TxContext) {
      let keys = vector[
        utf8(b"name"),
        utf8(b"symbol"),
        utf8(b"description"),
        utf8(b"project_url"),
        utf8(b"image_url"),
      ];

      let values = vector[
        utf8(b"Sui Yield"),
        utf8(b"SUIY"),
        utf8(b"This NFT accrues Sui rewards from Interest LSD"),
        utf8(b"https://www.interestprotocol.com"),
        utf8(b"ipfs://TODO"),
      ];

      let publisher = package::claim(witness, ctx);

      let display = display::new_with_fields<SuiYield>(&publisher, keys, values, ctx);
      display::update_version(&mut display);

      transfer::share_object(
        SuiYieldStorage {
          id: object::new(ctx),
          display,
        }
      );

      transfer::public_transfer(publisher, tx_context::sender(ctx));
  }

  /**
  * @dev Only friend packages can mint SUI_YIELD
  * @param storage The InterestSuiYNStorage
  * @param principal The SUI_YIELD minted in conjunction with this NFT
  * @param shares The iSUI assigned to this NFT
  * @return SuiYield
  */
  public(friend) fun mint(principal: u64, shares: u64, ctx: &mut TxContext): SuiYield {
    let nft_id = object::new(ctx);
    emit(Mint { nft_id: *object::uid_as_inner(&nft_id), principal, shares , sender: tx_context::sender(ctx) });
    
    SuiYield {
      id: nft_id,
      principal,
      shares,
      is_clean: true
    }
  }

  /**
  * @dev Only friend packages can burn SUI_YIELD
  * @param nft The NFT to burn
  * @return (shares, principal)
  */
  public(friend) fun burn(nft: SuiYield, ctx: &mut TxContext): (u64, u64) {
    emit(
      Burn { 
      nft_id: *object::uid_as_inner(&nft.id), 
      principal: nft.principal, 
      shares: nft.shares , 
      sender: tx_context::sender(ctx) 
      }
    );
    let SuiYield {id, principal, shares,  is_clean: _} = nft;
    object::delete(id);
    (principal, shares)
  }

  /**
  * @dev It allows the friend package to create a Join function
  * @param  nft The NFT to update
  * @param principal The new principal
  * @param shares The new shares
  */
  public(friend) fun update(nft: &mut SuiYield, principal: u64, shares: u64) {
    nft.principal = principal;
    nft.shares = shares;
  }

  /// ** UID Access 

  /// SuiYield UID to allow reading dynamic fields.
  public fun uid(nft: &SuiYield): &UID { &nft.id }

  /// Expose mutable access to the SuiYield `UID` to allow extensions.
  public fun uid_mut(nft: &mut SuiYield): &mut UID { 
    // If anyone ever calls this function, we assume it has a dynamic field.
    nft.is_clean = false;
    &mut nft.id 
  }

  /**
  * @dev It reads the shares and principal associated with an {SuiYield} nft
  */
  public fun read(nft: &SuiYield):(u64, u64) {
    (nft.principal, nft.shares)
  }

  /**
  * @dev Utility function to transfer Coin<SUI_YIELD>
  * @param The nft to transfer
  * @param recipient The address that will receive the Coin<SUI_YIELD>
  */
  public entry fun transfer(nft: SuiYield, recipient: address, _: &mut TxContext) {
    transfer::public_transfer(nft, recipient)
  }

  // ** Admin Functions - The admin can only update the Metadata

  public entry fun display_add_multiple(_: &AdminCap, storage: &mut SuiYieldStorage, keys: vector<String>, values: vector<String>) {
    display::add_multiple(&mut storage.display, keys, values);
  }

  public entry fun display_edit(_: &AdminCap, storage: &mut SuiYieldStorage, key: String, value: String) {
    display::edit(&mut storage.display, key, value);
  }

  public entry fun display_remove(_: &AdminCap, storage: &mut SuiYieldStorage, key: String) {
    display::remove(&mut storage.display, key);
  }

  public entry fun display_update_version(_: &AdminCap, storage: &mut SuiYieldStorage) {
    display::update_version(&mut storage.display);
  }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SUI_YIELD {}, ctx);
  }

  #[test_only]
  /// Mint nfts of any type for (obviously!) testing purposes only
  public fun mint_for_testing(principal: u64, shares: u64, ctx: &mut TxContext): SuiYield {
      SuiYield {
        id: object::new(ctx),
        principal,
        shares,
        is_clean: true
    }
  }

  #[test_only]
  public fun burn_for_testing(nft: SuiYield) {
    let SuiYield {id, principal: _, shares: _, is_clean: _} = nft;
    object::delete(id);
  }
}