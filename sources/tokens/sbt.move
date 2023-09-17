/// This module provide the building blocks to design incentive mechanisms on Interest and DeFi on Sui
/// Users mint a SoulBoundToken that is used to lock assets in a non-custodial way and store points
/// Points are accumulated by performing actions on Interest and other DeFi protocols, they can be redeemed for rewards
/// 
/// Developers can create their own module similar to `review` to "plug" their protocol on Interest's composable mechanism
/// while providing additional quests and rewards

module interest_lst::soulbound_token {
  use std::ascii::String;
  use std::type_name::{Self, TypeName};

  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID};
  use sui::tx_context::{Self, TxContext};
  use sui::table::{Self, Table};
  use sui::bag::{Self, Bag};
  use sui::dynamic_field as df;

  use interest_lst::semi_fungible_token::{Self as sft, SemiFungibleToken};

  const EStillLocked: u64 = 0;

  // only one instance of an asset can be locked at the same time
  struct LockedAsset<Asset: key + store> has store {
    unlock_epoch: u64,
    asset: Asset,
  }

  // soul bound token, cannot be transferred without custom function (no store ability)
  struct Interestore has key {
    id: UID,
    points: Table<String, u64>, // package_id => points (prevents sbt deletion when non empty)
    locked_assets: Bag, // type_name => LockedAsset (Coin or SFT)
    // package_id => object (dynamic object field for additional rewards, doesn't prevent sbt deletion if not empty)
  }

  // TODO we might want to restrict dynamic points field creation
  // struct PointsData has key {
  //   id: UID,
  //   whitelist: vector<address>,
  // }

  // TODO: need events

  // @dev create a SBT on sender wallet
  public fun mint_sbt(ctx: &mut TxContext) {
    transfer::transfer(
      Interestore {
        id: object::new(ctx),
        points: table::new(ctx),
        locked_assets: bag::new(ctx),
      },
      tx_context::sender(ctx)
    )
  }

  // @dev destroy an empty sbt (can still contain dynamic fields)
  public fun destroy_empty(sbt: Interestore) {
    let Interestore { id, points, locked_assets } = sbt;
    table::destroy_empty(points);
    bag::destroy_empty(locked_assets);
    object::delete(id);
  }

  // ** Points 

  // @dev add a dynamic field for points on the SBT
  /*
  * @param Witness: witness type for getting package id calling the function
  * @param sbt: soulbound token  
  * @param points: number of points to initialize the field (can be 0) 
  */
  public fun create_points<Witness: drop>(_: Witness, sbt: &mut Interestore, points: u64) {
    table::add(&mut sbt.points, package_id<Witness>(), points);
  }

  public fun add_points<Witness: drop>(w: Witness, sbt: &mut Interestore, points: u64) {
    let prev_points = borrow_mut_points(w, sbt);
    *prev_points = *prev_points + points;
  }

  public fun remove_points<Witness: drop>(w: Witness, sbt: &mut Interestore, points: u64) {
    let prev_points = borrow_mut_points(w, sbt);
    *prev_points = if (*prev_points > points) { *prev_points - points } else { 0 };
  }

  // @dev allows anyone to clear the points to empty the table 
  public fun clear_points(package_id: String, sbt: &mut Interestore): u64 {
    table::remove(&mut sbt.points, package_id)
  }

  // TODO we might want to restrict the access
  public fun borrow_mut_points<Witness: drop>(_: Witness, sbt: &mut Interestore): &mut u64 {
    table::borrow_mut<String, u64>(&mut sbt.points, package_id<Witness>())
  }

  public fun borrow_points<Witness: drop>(_: Witness, sbt: &Interestore): &u64 {
    table::borrow<String, u64>(&sbt.points, package_id<Witness>())
  }

  public fun read_points(package_id: String, sbt: &Interestore): &u64 {
    table::borrow<String, u64>(&sbt.points, package_id)
  }

  // ** Lock assets

  // @dev lock an asset for a specific number of epochs 
  /*
  * @param sbt: soulbound token  
  * @param asset: asset to lock
  * @param number_of_epochs: duration during which the asset should be locked
  */
  public fun lock_asset<Asset: key + store>(sbt: &mut Interestore, asset: Asset, number_of_epochs: u64, ctx: &mut TxContext) {
    let type = type_name::get<Asset>();
    let unlock_epoch = tx_context::epoch(ctx) + number_of_epochs;
    bag::add(&mut sbt.locked_assets, type, LockedAsset { unlock_epoch, asset });
  } 

  public fun unlock_asset<Asset: key + store>(sbt: &mut Interestore, ctx: &mut TxContext): Asset {
    let type = type_name::get<Asset>();

    let LockedAsset { unlock_epoch, asset } = bag::remove<TypeName, LockedAsset<Asset>>(&mut sbt.locked_assets, type);
    // verify the asset is no longer locked
    assert!(unlock_epoch < tx_context::epoch(ctx), EStillLocked);
    asset
  } 

  public fun lock_more_coin<T: drop>(sbt: &mut Interestore, new_coin: Coin<T>, number_of_epochs: u64, ctx: &mut TxContext) {
    let type = type_name::get<Coin<T>>();
    let new_epoch = tx_context::epoch(ctx) + number_of_epochs;
    let LockedAsset { unlock_epoch, asset } = bag::borrow_mut<TypeName, LockedAsset<Coin<T>>>(&mut sbt.locked_assets, type);

    *unlock_epoch = if (*unlock_epoch < tx_context::epoch(ctx)) {
      new_epoch
    } else {
      (new_epoch + *unlock_epoch) / 2
      // we could weight each unlock epoch with the amount of each asset
    };

    coin::join(asset, new_coin);
  } 

  public fun lock_more_sft<T: drop>(sbt: &mut Interestore, new_sft: SemiFungibleToken<T>, number_of_epochs: u64, ctx: &mut TxContext) {
    let type = type_name::get<SemiFungibleToken<T>>();
    let new_epoch = tx_context::epoch(ctx) + number_of_epochs;
    let LockedAsset { unlock_epoch, asset } = bag::borrow_mut<TypeName, LockedAsset<SemiFungibleToken<T>>>(&mut sbt.locked_assets, type);

    *unlock_epoch = if (*unlock_epoch < tx_context::epoch(ctx)) {
      new_epoch
    } else {
      (new_epoch + *unlock_epoch) / 2
      // we could weight each unlock epoch with the amount and slot of each asset
    };

    sft::join(asset, new_sft);
  } 

  public fun read_locked_coin<T: drop>(sbt: &Interestore): (u64, u64) {
    let type = type_name::get<Coin<T>>();
    let locked = bag::borrow<TypeName, LockedAsset<Coin<T>>>(&sbt.locked_assets, type);

    (locked.unlock_epoch, coin::value(&locked.asset))
  }

  public fun read_locked_sft<T: drop>(sbt: &Interestore): (u64, u256, u64) {
    let type = type_name::get<Coin<T>>();
    let locked = bag::borrow<TypeName, LockedAsset<SemiFungibleToken<T>>>(&sbt.locked_assets, type);

    (locked.unlock_epoch, sft::slot(&locked.asset), sft::value(&locked.asset))
  }

  // ** Arbitrary dynamic fields

  // @dev add a dynamic field on the SBT that can be any storable struct
  /*
  * @param Witness: witness type for getting package id calling the function
  * @param sbt: soulbound token  
  * @param field: field to append 
  */
  public fun create_field<Witness: drop, Field: store>(_: Witness, sbt: &mut Interestore, field: Field) {
    df::add(borrow_uid_mut(sbt), package_id<Witness>(), field);
  }

  public fun remove_field<Witness: drop, Field: store>(_: Witness, sbt: &mut Interestore): Field {
    df::remove(borrow_uid_mut(sbt), package_id<Witness>())
  }

  public fun borrow_mut_field<Witness: drop, Field: store>(_: Witness, sbt: &mut Interestore): &mut Field {
    df::borrow_mut<String, Field>(borrow_uid_mut(sbt), package_id<Witness>())
  }

  public fun borrow_field<Witness: drop, Field: store>(_: Witness, sbt: &Interestore): &Field {
    df::borrow<String, Field>(borrow_uid(sbt), package_id<Witness>())
  }

  // TODO we might want to expose it to open more use cases
  fun borrow_uid_mut(sbt: &mut Interestore): &mut UID {
    &mut sbt.id
  } 

  fun borrow_uid(sbt: &Interestore): &UID {
    &sbt.id
  }

  fun package_id<Witness: drop>(): String {
    let type = type_name::get<Witness>();
    type_name::get_address(&type)
  } 

} 