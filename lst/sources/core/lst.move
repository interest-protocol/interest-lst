// @Authors - JMVC <> Thouny
// This contract manages the minting/burning of iSui, iSUIP, and iSUIY
// iSui is a share of the total SUI principal + rewards this module owns
// iSUIP is always 1 SUI as it represents the principal owned by this module
// iSUIY represents the yield component of a iSUIP
module interest_lst::interest_lst { 
  use sui::sui::SUI;
  use sui::balance::Balance;
  use sui::object::{Self, UID};
  use sui::dynamic_field as df;
  use sui::tx_context::TxContext;
  use sui::transfer::share_object;
  use sui::linked_table::LinkedTable;
  use sui::coin::{Coin, TreasuryCap};

  use sui_system::sui_system::SuiSystemState;
  use sui_system::staking_pool::StakedSui;

  use suitears::fund::Fund;
  use suitears::semi_fungible_token::{SemiFungibleToken, SftTreasuryCap};

  use yield::yield::{Yield, YieldCap};

  use interest_lst::isui::ISUI;
  use interest_lst::fee_utils::Fee;
  use interest_lst::lst_admin::LstAdmin;
  use interest_lst::validator::Validator;
  use interest_lst::isui_yield::ISUI_YIELD;
  use interest_lst::unstake_utils::UnstakePayload;
  use interest_lst::isui_principal::ISUI_PRINCIPAL;
  use interest_lst::interest_lst_inner_state::{Self as inner_state, State};

  // ** Structs

  struct StateKey has store, drop, copy {}

  struct InterestLST has key {
    id: UID
  }

  fun init(ctx: &mut TxContext) {
    share_object(InterestLST { id: object::new(ctx) });
  }

  // @dev this function cannot be called again because the caps cannot be created again
  public fun create_genesis_state(
    self: &mut InterestLST,
    isui_cap: TreasuryCap<ISUI>,
    principal_cap: SftTreasuryCap<ISUI_PRINCIPAL>,
    yield_cap: YieldCap<ISUI_YIELD>,
    ctx: &mut TxContext
  ) {
    let genesis_state = inner_state::create_genesis_state(isui_cap, principal_cap, yield_cap, ctx);
    df::add(&mut self.id, StateKey {}, genesis_state);
  }

  public fun get_exchange_rate_isui_to_sui(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    isui_amount: u64,
    ctx: &mut TxContext
  ): u64 {
    let state = load_state_mut(self);
    inner_state::get_exchange_rate_isui_to_sui(sui_state, state, isui_amount, ctx)
  }

  public fun get_exchange_rate_sui_to_isui(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    sui_amount: u64,
    ctx: &mut TxContext
  ): u64 {
    let state = load_state_mut(self);
    inner_state::get_exchange_rate_sui_to_isui(sui_state, state, sui_amount, ctx)
  }

  public fun get_pending_yield(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    coupon: &Yield<ISUI_YIELD>,
    ctx: &mut TxContext  
  ): u64 {
    let state = load_state_mut(self);
    inner_state::get_pending_yield(sui_state, state, coupon,  ctx)
  }

  public fun update_pool(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    ctx: &mut TxContext,
  ) {
    let state = load_state_mut(self);
    inner_state::update_pool(sui_state, state, ctx);
  }

  public fun mint_isui(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    asset: Coin<SUI>,
    validator_address: address,
    ctx: &mut TxContext,
  ): Coin<ISUI> {
    let state = load_state_mut(self);
    inner_state::mint_isui(sui_state, state, asset, validator_address, ctx)
  }

  public fun burn_isui(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    asset: Coin<ISUI>,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext
  ): Coin<SUI> {
    let state = load_state_mut(self);
    inner_state::burn_isui(sui_state, state, asset, validator_address, unstake_payload, ctx)
  }

  public fun mint_stripped_bond(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    asset: Coin<SUI>,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext    
  ): (SemiFungibleToken<ISUI_PRINCIPAL>, Yield<ISUI_YIELD>) {
    let state = load_state_mut(self);
    inner_state::mint_stripped_bond(sui_state, state, asset, validator_address, maturity, ctx)
  }

  public fun call_bond(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    principal: SemiFungibleToken<ISUI_PRINCIPAL>,
    coupon: Yield<ISUI_YIELD>,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,    
  ): Coin<SUI> {
    let state = load_state_mut(self);
    inner_state::call_bond(sui_state, state, principal, coupon, validator_address, unstake_payload, ctx)
  }

  public fun burn_sui_principal(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    principal: SemiFungibleToken<ISUI_PRINCIPAL>,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ): Coin<SUI> {
    let state = load_state_mut(self);
    inner_state::burn_sui_principal(sui_state, state, principal, validator_address, unstake_payload, ctx)
  }

  public fun claim_yield(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    coupon: Yield<ISUI_YIELD>,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ): (Yield<ISUI_YIELD>, Coin<SUI>) {
    let state = load_state_mut(self);
    inner_state::claim_yield(sui_state, state, coupon, validator_address, unstake_payload,  ctx)
  }

  // ** DAO Functions

  public fun whitelist_validators(_: &LstAdmin, self: &mut InterestLST, new_whitelist: vector<address>) {
    let state = load_state_mut(self);
    inner_state::whitelist_validators(state, new_whitelist);
  }

  public fun update_fee(_: &LstAdmin, self: &mut InterestLST, new_fee: Fee) {
    let state = load_state_mut(self);
    inner_state::update_fee(state, new_fee);
  }

  public fun take_dao_balance(_: &LstAdmin, self: &mut InterestLST, ctx: &mut TxContext): Coin<ISUI> {
    let state = load_state_mut(self);
    inner_state::take_dao_balance(state, ctx)
  }

  // ** Read only Functions

  public fun is_whitelisted(self: &mut InterestLST, validator_address: address): bool {
    let state = load_state_mut(self);
    inner_state::is_whitelisted(state, validator_address)
  }


  public fun read_state(self: &mut InterestLST): (&Fund, u64, &LinkedTable<address, Validator>, u64, &Fee, &Balance<ISUI>, &LinkedTable<u64, Fund>) {
    let state = load_state_mut(self);
    inner_state::read_state(state)
  }

  public fun read_validator(self: &mut InterestLST, validator_address: address): (&LinkedTable<u64, StakedSui>, u64) {
    let state = load_state_mut(self);
    inner_state::read_validator(state, validator_address)  
  }


  // ** Private Functions

  fun load_state_mut(self: &mut InterestLST): &mut State {
    df::borrow_mut(&mut self.id, StateKey {})
  }

  // ** Test Functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }

  #[test_only]
  public fun borrow_mut_caps(self: &mut InterestLST): (&mut TreasuryCap<ISUI>, &mut SftTreasuryCap<ISUI_PRINCIPAL>, &mut YieldCap<ISUI_YIELD>) {
    let state = load_state_mut(self);
    inner_state::borrow_mut_caps(state)
  }
}
