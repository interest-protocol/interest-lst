module interest_lst::entry {
  use sui::sui::SUI;
  use sui::coin::Coin;
  use sui::tx_context::{Self, TxContext};

  use sui_system::sui_system::SuiSystemState;

  use interest_lst::isui::ISUI;
  use interest_lst::isui_yield::ISUI_YIELD;
  use interest_lst::unstake_utils::UnstakePayload;
  use interest_lst::isui_principal::ISUI_PRINCIPAL;
  use interest_lst::interest_lst::{Self, InterestLST};
  use interest_lst::asset_utils::{
    handle_coin_vector, 
    handle_yield_vector,
    public_transfer_coin,
    public_transfer_yield,
    handle_principal_vector,
    public_transfer_principal
  };

  use yield::yield::Yield;

  use suitears::semi_fungible_token::SemiFungibleToken;

  entry fun mint_isui(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    assets: vector<Coin<SUI>>,
    asset_value: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(interest_lst::mint_isui(
      sui_state,
      self,
      handle_coin_vector(assets, asset_value, ctx),
      validator_address,
      ctx
    ), tx_context::sender(ctx));
  }

  public fun burn_isui(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    assets: vector<Coin<ISUI>>,
    asset_value: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(interest_lst::burn_isui(
      sui_state,
      self,
      handle_coin_vector(assets, asset_value, ctx),
      validator_address,
      unstake_payload,
      ctx
    ), tx_context::sender(ctx));
  }

  entry fun mint_stripped_bond(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    assets: vector<Coin<SUI>>,
    asset_value: u64,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ) {
    let (principal, yield) = interest_lst::mint_stripped_bond(
      sui_state,
      self,
      handle_coin_vector(assets, asset_value, ctx),
      validator_address,
      maturity,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_principal(principal, sender);
    public_transfer_yield(yield, sender);
  }

  public fun call_bond(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    principal_vector: vector<SemiFungibleToken<ISUI_PRINCIPAL>>,
    yield_vector: vector<Yield<ISUI_YIELD>>,
    principal_value: u64,
    yield_value: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(
      interest_lst::call_bond(
        sui_state,
        self,
        handle_principal_vector(principal_vector, principal_value, ctx),
        handle_yield_vector(yield_vector, yield_value, ctx),
        validator_address,
        unstake_payload,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

  public fun burn_sui_principal(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    principal_vector: vector<SemiFungibleToken<ISUI_PRINCIPAL>>,
    principal_value: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(
      interest_lst::burn_sui_principal(
        sui_state,
        self,
        handle_principal_vector(principal_vector, principal_value, ctx),
        validator_address,
        unstake_payload,
        ctx
      ),
      tx_context::sender(ctx))
  }

  public fun claim_yield(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    yield_vector: vector<Yield<ISUI_YIELD>>,
    yield_value: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ) {
    let (yield, coin_sui) = interest_lst::claim_yield(
      sui_state,
      self,
      handle_yield_vector(yield_vector, yield_value, ctx),
      validator_address,
      unstake_payload,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_yield(yield, sender);
    public_transfer_coin(coin_sui, sender);
  }
}