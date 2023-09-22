/// This module provide the building blocks to design incentive mechanisms on Interest and DeFi on Sui
/// Users mint a SoulBoundToken that is used to lock assets in a non-custodial way and store points
/// Points are accumulated by performing actions on Interest and other DeFi protocols, they can be redeemed for rewards
/// 
/// Developers can create their own module similar to `review` to "plug" their protocol on Interest's composable mechanism
/// while providing additional quests and rewards

module interest_lst::soulbound_token {
  use std::vector;
  use std::string;
  use std::ascii::String;
  use std::type_name::{Self, TypeName};

  use sui::transfer;
  use sui::event::emit;
  use sui::bag::{Self, Bag};
  use sui::table::{Self, Table};
  use sui::object::{Self, UID, ID};
  use sui::display::{Self, Display};
  use sui::tx_context::{Self, TxContext};
  use sui::package::{Self, published_package, Publisher};

  use interest_lst::admin::AdminCap;

  const TEN_YEARS: u64 = 3_650;

  const EStillLocked: u64 = 0;
  const ETooLong: u64 = 1;

  struct SOULBOUND_TOKEN has drop {}

  // only one instance of an asset can be locked at the same time
  struct LockedAsset<Asset: key + store> has store {
    unlock_epoch: u64,
    assets: vector<Asset>,
  }

  // soul bound token, CANNOT be transferred without custom function (no store ability)
  // soul bound can only be destroyed if it has no points and no locked assets
  struct InterestSBT has key {
    id: UID,
    points: Table<String, u64>, // package_id => points (prevents sbt deletion when non empty)
    locked_assets: Bag, // type_name => LockedAsset (Any object with store + key)
    // package_id => object (dynamic object field for additional rewards, doesn't prevent sbt deletion if not empty)
  }

  struct Storage has key {
    id: UID,
    display: Display<InterestSBT>,
    publisher: Publisher
  }

  // ** Events

  struct MintSBT has drop, copy {
    sender: address,
    sbt_id: ID
  }

  struct DestroySBT has drop, copy {
    sender: address,
  }

  fun init(otw: SOULBOUND_TOKEN, ctx: &mut TxContext) {
    let keys = vector[
      string::utf8(b"name"),
      string::utf8(b"image_url"),
      string::utf8(b"description"),
      string::utf8(b"project_url"),
    ];

    let values = vector[
      string::utf8(b"Interest Protocol Soulbound Token"),
      string::utf8(b"https://interestprotocol.infura-ipfs.io/ipfs/QmSG6xHk6hiaCur3AifAXV1ZaMfPpARn2xqCsBP9sWEYHg"),
      string::utf8(b"This Soulbound token allows users to attain points in various DeFi protocols by locking up assets."),
      string::utf8(b"https://www.interestprotocol.com/"),      
    ];

    // Claim the `Publisher` for the package!
    let publisher = package::claim(otw, ctx);

    let display = display::new_with_fields<InterestSBT>(&publisher, keys, values, ctx);

    // Commit first version of `Display` to apply changes.
    display::update_version(&mut display);

    transfer::share_object(Storage {id: object::new(ctx), display, publisher });
  }

   // ** CREATE/DESTROY SBTs

  // @dev create a SBT on sender wallet
  public fun mint_sbt(ctx: &mut TxContext) {
    let sbt = InterestSBT {
        id: object::new(ctx),
        points: table::new(ctx),
        locked_assets: bag::new(ctx),
    };
    let sender = tx_context::sender(ctx);
    
    emit(MintSBT {
      sender,
      sbt_id: object::id(&sbt)
    });

    transfer::transfer(sbt, sender);
  }

  // @dev destroy an empty sbt (can still contain dynamic fields)
  /*
  * @param sbt The empty SBT that will be destroyed
  */
  public fun destroy_empty(sbt: InterestSBT, ctx: &mut TxContext) {
    let InterestSBT { id, points, locked_assets } = sbt;
    table::destroy_empty(points);
    bag::destroy_empty(locked_assets);
    object::delete(id);
    emit(DestroySBT {sender: tx_context::sender(ctx) });
  }

  // ** READ Points API

  // @dev Read how many points the SBT has for a {package_id}
  /*
  * @param package_id A package id
  * @param sbt The SBT we will read its points
  */
  public fun read_points(package_id: String, sbt: &InterestSBT): &u64 {
    table::borrow<String, u64>(&sbt.points, package_id)
  }

  // @dev Check if the SBT contains points from a {package_id}
  /*
  * @param package_id A package id
  * @param sbt The SBT we will check its points
  */
  public fun contains_points(package_id: String, sbt: &InterestSBT): bool {
    table::contains<String, u64>(&sbt.points, package_id)
  }

  // ** WRITE Points API

  // @dev add a dynamic field for points on the SBT
  /*
  * @param publisher: Publisher of the package that will manage the points
  * @param sbt: soulbound token  
  * @param points: number of points to initialize the field (can be 0) 
  */
  public fun create_points(publisher: &Publisher, sbt: &mut InterestSBT, points: u64) {
    table::add(&mut sbt.points, *published_package(publisher), points);
  }

  // @dev adds Points to the SBT for a {package}
  /*
  * @param publisher: Publisher of the package that will manage the points
  * @param sbt: soulbound token  
  * @param points: number of points to add
  */
  public fun add_points(publisher: &Publisher, sbt: &mut InterestSBT, points: u64) {
    let prev_points = borrow_mut_points(publisher, sbt);
    *prev_points = *prev_points + points;
  }

  // @dev removes Points to the SBT for a {package}
  /*
  * @param publisher: Publisher of the package that will manage the points
  * @param sbt: soulbound token  
  * @param points: number of points to remove
  */
  public fun remove_points(publisher: &Publisher, sbt: &mut InterestSBT, points: u64) {
    let prev_points = borrow_mut_points(publisher, sbt);
    *prev_points = if (*prev_points > points) { *prev_points - points } else { 0 };
  }

  // @dev allows the sender to clear their points to empty the table 
  /*
  * @param package_id: The package points field we wish to remove from the table 
  * @param sbt: The SBT
  */
  public fun clear_points(package_id: String, sbt: &mut InterestSBT): u64 {
    table::remove(&mut sbt.points, package_id)
  }

  // ** Private Functions

  // @dev The publisher should use the available API to manage points
  fun borrow_mut_points(publisher: &Publisher, sbt: &mut InterestSBT): &mut u64 {
    table::borrow_mut<String, u64>(&mut sbt.points, *published_package(publisher))
  }

  // ** Lock assets

  // @dev lock an asset for a specific number of epochs 
  // ** IMPORTANT there is no way to unlock before the locked period
  /*
  * @param sbt: soulbound token  
  * @param asset: asset to lock
  * @param number_of_epochs: duration during which the asset should be locked
  */
  public fun lock_asset<Asset: key + store>(sbt: &mut InterestSBT, asset: Asset, number_of_epochs: u64, ctx: &mut TxContext) {
    // We add a maximum of ten years
    assert!(TEN_YEARS >= number_of_epochs, ETooLong);
    let type = type_name::get<Asset>();
    let unlock_epoch = tx_context::epoch(ctx) + number_of_epochs;
    bag::add(&mut sbt.locked_assets, type, LockedAsset { unlock_epoch, assets: vector::singleton(asset) });
  } 

  // @dev User can only unlock an asset after the unlock period
  /*
  * @param sbt: soulbound token  
  * @param asset: asset to lock
  * @param number_of_epochs: duration during which the asset should be locked
  */
  public fun unlock_asset<Asset: key + store>(sbt: &mut InterestSBT, ctx: &mut TxContext): vector<Asset> {
    let type = type_name::get<Asset>();

    let LockedAsset { unlock_epoch, assets } = bag::remove<TypeName, LockedAsset<Asset>>(&mut sbt.locked_assets, type);
    // verify the asset is no longer locked
    assert!(unlock_epoch < tx_context::epoch(ctx), EStillLocked);
    assets
  } 

  // @dev User can lock more assets and extend the lock period
  /*
  * @param sbt: soulbound token  
  * @param asset: asset to lock
  * @param number_of_epochs: duration during which the asset should be locked
  */
  public fun lock_more_asset<Asset: key + store>(sbt: &mut InterestSBT, new_asset: Asset, number_of_epochs: u64, ctx: &mut TxContext) {
    let type = type_name::get<Asset>();
    let new_epoch = tx_context::epoch(ctx) + number_of_epochs;
    let LockedAsset { unlock_epoch, assets } = bag::borrow_mut<TypeName, LockedAsset<Asset>>(&mut sbt.locked_assets, type);

    *unlock_epoch = if (*unlock_epoch < tx_context::epoch(ctx)) {
      new_epoch
    } else {
      (new_epoch + *unlock_epoch) / 2
      // we could weight each unlock epoch with the amount of each asset
    };

    vector::push_back(assets, new_asset);
  } 

  // @dev Allows a user to read how many assets he locked and the lock period
  /*
  * @param sbt: soulbound token  
  * @param asset: asset to lock
  * @param number_of_epochs: duration during which the asset should be locked
  */
  public fun read_locked_asset<Asset: key + store>(sbt: &InterestSBT): (&vector<Asset>, u64) {
    let type = type_name::get<Asset>();
    let lock = bag::borrow<TypeName, LockedAsset<Asset>>(&sbt.locked_assets, type);
    (&lock.assets, lock.unlock_epoch)
  }

  // ** Arbitrary dynamic fields

  public fun borrow_uid_mut(sbt: &mut InterestSBT): &mut UID {
    &mut sbt.id
  } 

  public fun borrow_uid(sbt: &InterestSBT): &UID {
    &sbt.id
  }

  // ** Display API Admin Only

  /// Sets multiple fields at once
  public fun add_multiple(_: &AdminCap, storage: &mut Storage, keys: vector<string::String>, values: vector<string::String>) { 
    display::add_multiple(&mut storage.display, keys, values)    
  }

  /// Edit a single field
  public fun edit(_: &AdminCap, storage: &mut Storage, key: string::String, value: string::String) { 
    display::edit(&mut storage.display, key, value);  
  }

  /// Remove a key from Display
  public fun remove(_: &AdminCap, storage: &mut Storage, key: string::String) { 
    display::remove(&mut storage.display, key);
  }

} 