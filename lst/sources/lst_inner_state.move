module interest_lst::interest_lst_inner_state { 

  use sui::sui::SUI;
  use sui::object::{Self, UID, ID};
  use sui::balance::{Self, Balance};
  use sui::coin::{Self, TreasuryCap};
  use sui::versioned::{Self, Versioned};
  use sui::tx_context::{Self, TxContext};
  use sui::linked_table::{Self, LinkedTable};

  use suitears::fund::{Self, Fund};
  use suitears::semi_fungible_token::{Self, SftTreasuryCap};

  use yield::yield::{Self, YieldCap};
  
  use interest_lst::isui::ISUI;
  use interest_lst::isui_yield::ISUI_YIELD;
  use interest_lst::validator::{Self, Validator};
  use interest_lst::isui_principal::ISUI_PRINCIPAL;
  use interest_lst::fee_utils::{new as new_fee, calculate_fee_percentage, set_fee, Fee};

  const STATE_VERSION_V1: u64 = 1;

  // Errors
  const EInvalidVersion: u64 = 0;

  friend interest_lst::interest_lst;

  struct StateV1 has store {
    pool: Fund, // This struct holds the total shares of ISUI and the total SUI (Principal + Rewards). Rebase {base: ISUI total supply, elastic: total Sui}
    last_epoch: u64, // Last epoch that pool was updated
    validators_table: LinkedTable<address, Validator>, // We need a linked table to iterate through all validators once every epoch to ensure all pool data is accurate
    total_principal: u64, // Total amount of StakedSui principal deposited in Interest lst Package
    fee: Fee, // Holds the data to calculate the stake fee
    whitelist_validators: vector<address>,
    pool_history: LinkedTable<u64, Fund>, // Epoch => Pool Data
    dust: Balance<SUI>, // If there is less than 1 Sui from unstaking (rewards)
    dao_balance: Balance<ISUI>, // Fees collected by the protocol in ISUI
    rate: u64, // Weighted APY Arithmetic mean
    total_activate_staked_sui: u64,
    isui_cap: TreasuryCap<ISUI>,
    principal_cap: SftTreasuryCap<ISUI_PRINCIPAL>,
    yield_cap: YieldCap<ISUI_YIELD>
  }

  struct State has store {
    inner: Versioned
  }

  public(friend) fun create_genesis_state(
    isui_cap: TreasuryCap<ISUI>,
    principal_cap: SftTreasuryCap<ISUI_PRINCIPAL>,
    yield_cap: YieldCap<ISUI_YIELD>,
    ctx: &mut TxContext
  ): State {
   let state_v1 = StateV1 {
      pool: fund::empty(),
      last_epoch: 0,
      validators_table: linked_table::new(ctx),
      total_principal: 0,
      fee: new_fee(),
      whitelist_validators: vector[],
      pool_history: linked_table::new(ctx),
      dust: balance::zero(),
      dao_balance: balance::zero(),
      rate: 0,
      total_activate_staked_sui: 0,
      isui_cap,
      principal_cap,
      yield_cap
    };

    State {
      inner: versioned::create(STATE_VERSION_V1, state_v1, ctx)
    }
  }

  fun load_state(self: &mut State): &StateV1 {
    load_state_maybe_upgrade(self)
  }

  fun load_state_mut(self: &mut State): &mut StateV1 {
    load_state_maybe_upgrade(self)
  }

  /// This function should always return the latest supported version.
  /// If the inner version is old, we upgrade it lazily in-place.
  fun load_state_maybe_upgrade(self: &mut State): &mut StateV1 {
    upgrade_to_latest(self);
    versioned::load_value_mut(&mut self.inner)
  }

  fun upgrade_to_latest(self: &mut State) {
    // TODO: When new versions are added, we need to explicitly upgrade here.
    assert!(versioned::version(&self.inner) == STATE_VERSION_V1, EInvalidVersion);
  }

}