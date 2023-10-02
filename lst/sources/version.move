module interest_lst::version {

  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::tx_context::{Self, TxContext};

  use interest_lst::errors;

 // Manually Increment this each time the protocol upgrades.
  const CURRENT_VERSION: u64 = 1;
  const SENTINEL_VALUE: u64 = 18446744073709551615;
  const TIME_DELAY: u64 = 2;

  friend interest_lst::pool;

  struct VersionTimelock has key {
    id: UID,
    start_time: u64
  }

  fun init(ctx: &mut TxContext) {
    transfer::share_object(
      VersionTimelock {
        id: object::new(ctx),
        start_time: SENTINEL_VALUE
      }
    );
  }


  public(friend) fun start_upgrade(timelock: &mut VersionTimelock, ctx: &mut TxContext) {
    timelock.start_time = tx_context::epoch(ctx);
  }

  public(friend) fun cancel_upgrade(timelock: &mut VersionTimelock) {
    timelock.start_time = SENTINEL_VALUE;
  }

  public(friend) fun upgrade(timelock: &mut VersionTimelock, ctx: &mut TxContext) {
    assert!(tx_context::epoch(ctx) > timelock.start_time + TIME_DELAY, errors::upgrade_locked());
    timelock.start_time = SENTINEL_VALUE;
  }

  public fun current_version(): u64 {
    CURRENT_VERSION
  }
}