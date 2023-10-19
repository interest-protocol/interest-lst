module interest_lst::validator {

  use sui::object::ID;
  use sui::versioned::{Self, Versioned};
  use sui::linked_table::{Self, LinkedTable};
  use sui::tx_context::TxContext;

  use sui_system::staking_pool::{Self, StakedSui};

  use interest_lst::errors;

  friend interest_lst::interest_lst_inner_state;

  const VALIDATOR_VERSION_V1: u64 = 1;

  struct ValidatorV1 has store {
    staking_pool_id: ID, // The ID of the Validator's {StakingPool}
    staked_sui_table: LinkedTable<u64, StakedSui>, // activation_epoch => StakedSui
    total_principal: u64 // Total amount of StakedSui principal deposited in this validator
  }

  struct Validator has store {
    inner: Versioned
  }

  public(friend) fun create_genesis_state(staking_pool_id: ID, ctx: &mut TxContext): Validator {
    let validator_v1 = ValidatorV1 {
      staking_pool_id,
      staked_sui_table: linked_table::new(ctx),
      total_principal: 0
    };

    Validator {
      inner: versioned::create(VALIDATOR_VERSION_V1, validator_v1, ctx)  
    }
  }

  public(friend) fun staking_pool_id(self: &mut Validator): ID {
    let validator = load_state(self);
    validator.staking_pool_id
  }

  public(friend) fun total_principal(self: &mut Validator): u64 {
    let validator = load_state(self);
    validator.total_principal
  }

  public(friend) fun borrow_mut_staked_sui_table(self: &mut Validator): &mut LinkedTable<u64, StakedSui> {
    let validator = load_state_mut(self);
    &mut validator.staked_sui_table    
  }

  public(friend) fun borrow_staked_sui_table(self: &mut Validator): &LinkedTable<u64, StakedSui> {
    let validator = load_state(self);
    &validator.staked_sui_table    
  }

  fun load_state(self: &mut Validator): &ValidatorV1 {
    load_state_maybe_upgrade(self)
  }

  fun load_state_mut(self: &mut Validator): &mut ValidatorV1 {
    load_state_maybe_upgrade(self)
  }

  /// This function should always return the latest supported version.
  /// If the inner version is old, we upgrade it lazily in-place.
  fun load_state_maybe_upgrade(self: &mut Validator): &mut ValidatorV1 {
    upgrade_to_latest(self);
    versioned::load_value_mut(&mut self.inner)
  }

  fun upgrade_to_latest(self: &mut Validator) {
    // TODO: When new versions are added, we need to explicitly upgrade here.
    assert!(versioned::version(&self.inner) == VALIDATOR_VERSION_V1, errors::invalid_version());
  }
}