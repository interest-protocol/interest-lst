module interest_lst::points {
  
  use std::ascii::String;

  use sui::sui::SUI;
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;
  use sui::balance::{Self, Balance};

  use sui_system::sui_system::SuiSystemState;
  
  use interest_lst::admin::AdminCap;
  use interest_lst::review::{Self, Reviews};
  use interest_lst::soulbound_token::{Self as sbt, InterestSBT};

  // This struct exist for the SBT to get the address of this package
  // It does need to be a OTW
  struct Any has drop {}

  struct Actions has key {
    id: UID,
    creation: u64,
    update: u64,
    deletion: u64,
  }

  // TODO: max_claimable_rewards not very useful since a user can still claim many times
  struct Rewards has key {
    id: UID,
    rewards_per_point: u64,
    max_claimable_rewards: u64,
    rewards: Balance<SUI>,
  }

  fun init(ctx: &mut TxContext) {
    transfer::share_object(Actions {id: object::new(ctx), creation: 0, update: 0, deletion: 0});
    transfer::share_object(Rewards {id: object::new(ctx), rewards_per_point: 0, max_claimable_rewards: 0, rewards: balance::zero()});
  }

  // ** Wrappers for review actions while adding points

  // @dev create a review by adding points to the SBT, need to create one in the PTB before if user doesn't have one
  /*
  * @param system: Sui system state (with validators data)
  * @param reviews: global storage 
  * @param points: storage for points depending on action
  * @param sbt: soulbound token 
  * @param validator_address: the validator to review
  * @param vote: up/down vote
  * @param comment: maximum 140 characters explaining the choice
  */
  public fun create_review(
    system: &mut SuiSystemState,
    reviews: &mut Reviews, 
    points: &Actions,
    sbt: &mut InterestSBT,
    validator_address: address,
    vote: bool,
    comment: String,
    ctx: &mut TxContext
  ) {
    review::create(system, reviews, sbt, validator_address, vote, comment, ctx);

    if (sbt::contains_points<Any>( sbt)) {
      sbt::create_points<Any>(sbt, 0);
    };

    sbt::add_points<Any>(sbt, points.creation);
  }

  // @dev update a review by adding points to the SBT
  public fun update_review(
    reviews: &mut Reviews, 
    points: &Actions,
    sbt: &mut InterestSBT,
    validator_address: address,
    vote: bool,
    comment: String,
    ctx: &mut TxContext
  ) {
    review::update(reviews, sbt, validator_address, vote, comment, ctx);

    sbt::add_points<Any>(sbt, points.update);
  }

  // @dev delete a review by adding points to the SBT, no need for the SuiYield sft
  public fun delete_review(
    reviews: &mut Reviews, 
    points: &Actions,
    sbt: &mut InterestSBT,
    validator_address: address,
    ctx: &mut TxContext
  ) {
    review::delete(reviews, validator_address, ctx);

    sbt::add_points<Any>(sbt, points.deletion);
  }

  // @dev claim the rewards depending on the points in the sbt and params
  /*
  * @param pool: storage with rewards pool
  * @param sbt: soulbound token with points
  * @return the rewards 
  */
  public fun claim_rewards(pool: &mut Rewards, sbt: &mut InterestSBT, ctx: &mut TxContext): Coin<SUI> {
    let points = sbt::read_points<Any>(sbt);
    let rewards = *points * pool.rewards_per_point;

    if (rewards > pool.max_claimable_rewards) {
      sbt::remove_points<Any>(sbt, *points - pool.max_claimable_rewards / pool.rewards_per_point);
      coin::take(&mut pool.rewards, pool.max_claimable_rewards, ctx)
    } else {
      sbt::remove_points<Any>(sbt, *points);
      coin::take(&mut pool.rewards, rewards, ctx)
    }
  }

  // @dev update the params for earning points
  /*
  * @param Admin: admin cap
  * @param storage: params storage for points 
  * @param creation: how many points gives a review creation
  * @param update: how many points gives a review update
  * @param deletion: how many points gives a review deletion
  */
  public fun set_review_points(_: &AdminCap, storage: &mut Actions, creation: u64, update: u64, deletion: u64) {
    storage.creation = creation;
    storage.update = update;
    storage.deletion = deletion;
  }

  // @dev update the rewards and params
  /*
  * @param Admin: admin cap
  * @param storage: rewards storage with balance and params 
  * @param rewards_per_point: how much rewards for a point (with decimals, 1 = 1 MIST)
  * @param max_claimable_rewards: maximum rewards claimable in this tx
  * @param rewards: rewards added to the pool
  */
  public fun set_rewards(_: &AdminCap, storage: &mut Rewards, rewards_per_point: u64, max_claimable_rewards: u64, rewards: Coin<SUI>) {
    storage.rewards_per_point = rewards_per_point;
    storage.max_claimable_rewards = max_claimable_rewards;
    coin::put(&mut storage.rewards, rewards);
  }
}