// Sui Liquid Staking Yield NFT
// It accrues rewards from Interest LSD Pool
module interest_lsd::isui_yn {
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
  struct ISuiYield has key, store {
    id: UID,
    img_url: String,
    principal: u64,
    shares: u64,
    is_frozen: bool
  }

  // OTW to create the Interest Sui LSD
  struct ISUI_YN has drop {}

  // Display Wrapper + img_url controller
  struct InterestSuiYNStorage has key {
    id: UID,
    display: Display<ISuiYield>,
    img_url: String
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

  struct Freeze has copy, drop {
    nft_id: ID,
    sender: address
  }

  struct Unfreeze has copy, drop {
    nft_id: ID,
    sender: address
  }

  fun init(witness: ISUI_YN, ctx: &mut TxContext) {
      let keys = vector[
        utf8(b"name"),
        utf8(b"symbol"),
        utf8(b"description"),
        utf8(b"project_url"),
        utf8(b"image_url"),
      ];

      let values = vector[
        utf8(b"iSui Yield NFT"),
        utf8(b"iSUI-YN"),
        utf8(b"This NFT accrues Sui rewards from Interest LSD"),
        utf8(b"https://www.interestprotocol.com"),
        utf8(b"ipfs://{img_url}"),
      ];

      let publisher = package::claim(witness, ctx);

      let display = display::new_with_fields<ISuiYield>(&publisher, keys, values, ctx);
      display::update_version(&mut display);

      transfer::share_object(
        InterestSuiYNStorage {
          id: object::new(ctx),
          display,
          // TODO Update
          img_url: utf8(b"")
        }
      );

      transfer::public_transfer(publisher, tx_context::sender(ctx));
  }

  /**
  * @dev Only friend packages can mint ISUI_YN
  * @param storage The InterestSuiYNStorage
  * @param principal The iSUI_PC minted in conjunction with this NFT
  * @param shares The iSUI assigned to this NFT
  * @return ISuiYield 
  */
  public(friend) fun mint(storage: &mut InterestSuiYNStorage, principal: u64, shares: u64, ctx: &mut TxContext): ISuiYield {
    let nft_id = object::new(ctx);
    emit(Mint { nft_id: *object::uid_as_inner(&nft_id), principal, shares , sender: tx_context::sender(ctx) });
    
    ISuiYield {
      id: nft_id,
      img_url: storage.img_url,
      principal,
      shares,
      is_frozen: false
    }
  }

  /**
  * @dev Only friend packages can burn ISUI_YN
  * @param nft The NFT to burn
  * @return (shares, principal)
  */
  public(friend) fun burn(nft: ISuiYield, ctx: &mut TxContext): (u64, u64) {
    emit(
      Burn { 
      nft_id: *object::uid_as_inner(&nft.id), 
      principal: nft.principal, 
      shares: nft.shares , 
      sender: tx_context::sender(ctx) 
      }
    );
    let ISuiYield {id, img_url: _, principal, shares,  is_frozen} = nft;
    object::delete(id);
    (principal, shares)
  }

  /**
  * @dev It allows the friend package to create a Join function
  * @param  nft The NFT to update
  * @param principal The new principal
  * @param shares The new shares
  */
  public(friend) fun update_nft(nft: &mut ISuiYield, principal: u64, shares: u64) {
    nft.principal = principal;
    nft.shares = shares;
  }

  /// ** UID Access 

  /// ISuiYield UID to allow reading dynamic fields.
  public fun uid(nft: &ISuiYield): &UID { &nft.id }

  /// Expose mutable access to the ISuiYield `UID` to allow extensions.
  public fun uid_mut(nft: &mut ISuiYield): &mut UID { &mut nft.id }

  /**
  * @dev It reads the shares and principal associated with an {ISuiYield} nft
  */
  public fun read_nft(nft: &ISuiYield):(u64, u64) {
    (nft.principal, nft.shares)
  }

  /// ** Freeze Mechanism
  
  // @dev It allows a holder to freeze it's NFT. Other modules can check if the NFT is frozen to prevent it from being burned
  // freeze is a restricted name
  /*
  * @param nft The NFT that will be frozen
  */
  public fun freeze_nft(nft: &mut ISuiYield, ctx: &mut TxContext) {
    nft.is_frozen = true;
    emit(Freeze { nft_id: *object::uid_as_inner(&nft.id), sender: tx_context::sender(ctx) });
  }

  // @dev It allows a holder to unfreeze its NFT.
  /*
  * @param nft The NFT that will be unfrozen
  */
  public fun unfreeze(nft: &mut ISuiYield, ctx: &mut TxContext) {
    nft.is_frozen = false;
    emit(Unfreeze { nft_id: *object::uid_as_inner(&nft.id), sender: tx_context::sender(ctx) });
  }

  // @dev It allows any caller to check if the NFT is frozen
  /*
  * @param nft The NFT in question
  */
  public fun is_frozen(nft: &ISuiYield): bool {
    nft.is_frozen
  }

  /**
  * @dev Utility function to transfer Coin<ISUI_YN>
  * @param The nft to transfer
  * @param recipient The address that will receive the Coin<ISUI_YN>
  */
  public entry fun transfer(nft: ISuiYield, recipient: address, _: &mut TxContext) {
    transfer::public_transfer(nft, recipient)
  }

  // ** Admin Functions - The admin can only update the Metadata

  /// Update img_url for new created NFTs
  public entry fun update_img_url(_: &AdminCap, storage: &mut InterestSuiYNStorage, img_url: String) {
    storage.img_url = img_url;
  }

  public entry fun display_add_multiple(_: &AdminCap, storage: &mut InterestSuiYNStorage, keys: vector<String>, values: vector<String>) {
    display::add_multiple(&mut storage.display, keys, values);
  }

  public entry fun display_edit(_: &AdminCap, storage: &mut InterestSuiYNStorage, key: String, value: String) {
    display::edit(&mut storage.display, key, value);
  }

  public entry fun display_remove(_: &AdminCap, storage: &mut InterestSuiYNStorage, key: String) {
    display::remove(&mut storage.display, key);
  }

  public entry fun display_update_version(_: &AdminCap, storage: &mut InterestSuiYNStorage) {
    display::update_version(&mut storage.display);
  }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ISUI_YN {}, ctx);
  }

  #[test_only]
  /// Mint nfts of any type for (obviously!) testing purposes only
  public fun mint_for_testing(principal: u64, shares: u64, ctx: &mut TxContext): ISuiYield {
      ISuiYield {
        id: object::new(ctx),
        img_url: utf8(b""),
        principal,
        shares,
        is_frozen: false
    }
  }

  #[test_only]
  public fun burn_for_testing(nft: ISuiYield) {
    let ISuiYield {id, img_url: _, principal: _, shares: _, is_frozen: _} = nft;
    object::delete(id);
  }
}