module interest_lst::validator {

  use sui::object::ID;
  use sui::versioned::{Self, Versioned};
  use sui::linked_table::{Self, LinkedTable};
  use sui::tx_context::TxContext;

  use sui_system::staking_pool::{Self, StakedSui};

  friend interest_lst::interest_lst_inner_state;

  const VALIDATOR_VERSION_V1: u64 = 1;

  // Errors
  const EInvalidVersion: u64 = 0;

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
    assert!(versioned::version(&self.inner) == VALIDATOR_VERSION_V1, EInvalidVersion);
  }
}