/// This module provide the building blocks to design incentive mechanisms on Interest and DeFi on Sui
/// Users mint a SoulBoundToken that is used to lock assets in a non-custodial way and store points
/// Points are accumulated by performing actions on Interest and other DeFi protocols, they can be redeemed for rewards
/// 
/// Developers can create their own module similar to `review` to "plug" their protocol on Interest's composable mechanism
/// while providing additional quests and rewards

module interest_lst::points {
  use std::vector;
  use std::ascii::{Self, String};
  use std::type_name::{Self, TypeName};

  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::event::{emit};
  use sui::object::{Self, UID, ID};
  use sui::tx_context::{Self, TxContext};
  use sui::table::{Self, Table};
  use sui::math;
  use sui::bag::{Self, Bag};
  use sui::dynamic_field as df;

  use interest_lst::sui_yield::{Self, SuiYield};
  use interest_lst::admin::AdminCap;
  use interest_lst::pool::{Self, PoolStorage};

  const EStillLocked: u64 = 0;

  // only one instance of an asset can be locked at the same time
  struct LockedAsset<Asset: key + store> has store {
    unlock_epoch: u64,
    asset: Asset,
  }

  // sould bound token, cannot be transferred without custom function (no store ability)
  struct Interestore has key {
    id: UID,
    locked_assets: Bag, // type_name => LockedAsset (Coin or SFT)
    // package_id => points (dynamic field)
  }

  // TODO we might want to restrict dynamic points field creation
  // struct PointsData has key {
  //   id: UID,
  //   whitelist: vector<address>,
  // }

  public fun mint_sbt(ctx: &mut TxContext) {
    transfer::transfer(
      Interestore {
        id: object::new(ctx),
        locked_assets: bag::new(ctx),
      },
      tx_context::sender(ctx)
    )
  }

  // ** Points 

  public fun create_points<Witness: drop>(_: Witness, sbt: &mut Interestore, points: u64) {
    let type = type_name::get<Witness>();
    let package = type_name::get_address(&type);
    df::add(borrow_uid_mut(sbt), package, points);
  }

  public fun add_points<Witness: drop>(w: Witness, sbt: &mut Interestore, points: u64) {
    let prev_points = borrow_mut_points(w, sbt);
    *prev_points = *prev_points + points;
  }

  public fun remove_points<Witness: drop>(w: Witness, sbt: &mut Interestore, points: u64) {
    let prev_points = borrow_mut_points(w, sbt);
    *prev_points = if (*prev_points > points) { *prev_points - points } else { 0 };
  }

  // TODO we might want to restrict the access
  public fun borrow_mut_points<Witness: drop>(_: Witness, sbt: &mut Interestore): &mut u64 {
    let type = type_name::get<Witness>();
    let package = type_name::get_address(&type);
    df::borrow_mut<String, u64>(borrow_uid_mut(sbt), package)
  }

  public fun borrow_points<Witness: drop>(_: Witness, sbt: &mut Interestore): &u64 {
    let type = type_name::get<Witness>();
    let package = type_name::get_address(&type);
    df::borrow<String, u64>(borrow_uid_mut(sbt), package)
  }

  // ** Lock assets

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

  public fun lock_more() {} // add a quantity of an asset already locked

  // TODO we might want to expose it to open more use cases
  fun borrow_uid_mut(sbt: &mut Interestore): &mut UID {
    &mut sbt.id
  } 

} 