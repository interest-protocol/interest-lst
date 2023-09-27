module interest_lst::entry {
  use sui::sui::SUI;
  use sui::coin::Coin;
  use sui::tx_context::{Self, TxContext};

  use sui_system::sui_system::SuiSystemState;

  use interest_framework::semi_fungible_token::SemiFungibleToken;

  use interest_tokens::isui::{ISUI, InterestSuiStorage};
  use interest_tokens::sui_yield::{SuiYieldStorage, SuiYield};
  use interest_tokens::sui_principal::{SuiPrincipalStorage, SUI_PRINCIPAL};

  use interest_lst::pool::{Self, PoolStorage};
  use interest_lst::unstake_utils::UnstakePayload;
  use interest_lst::asset_utils::{
    handle_coin_vector, 
    handle_yield_vector,
    public_transfer_coin,
    public_transfer_yield,
    handle_principal_vector,
    public_transfer_principal
  };

  entry fun mint_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    tokens: vector<Coin<SUI>>,
    token_value: u64,
    validator_address: address,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(pool::mint_isui(
      wrapper,
      storage,
      interest_sui_storage,
      handle_coin_vector(tokens, token_value, ctx),
      validator_address,
      ctx
    ), tx_context::sender(ctx));
  }

  public fun burn_isui(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    tokens: vector<Coin<ISUI>>,
    token_value: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(pool::burn_isui(
      wrapper,
      storage,
      interest_sui_storage,
      handle_coin_vector(tokens, token_value, ctx),
      validator_address,
      unstake_payload,
      ctx
    ), tx_context::sender(ctx));
  }

  entry fun mint_stripped_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    interest_sui_storage: &mut InterestSuiStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    tokens: vector<Coin<SUI>>,
    token_value: u64,
    validator_address: address,
    maturity: u64,
    ctx: &mut TxContext,
  ) {
    let (principal, yield) = pool::mint_stripped_bond(
      wrapper,
      storage,
      interest_sui_storage,
      sui_principal_storage,
      sui_yield_storage,
      handle_coin_vector(tokens, token_value, ctx),
      validator_address,
      maturity,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_principal(principal, sender);
    public_transfer_yield(yield, sender);
  }

  public fun call_bond(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    sft_principal_vector: vector<SemiFungibleToken<SUI_PRINCIPAL>>,
    sft_yield_vector: vector<SuiYield>,
    principal_value: u64,
    yield_value: u64,
    maturity: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(
      pool::call_bond(
        wrapper,
        storage,
        sui_principal_storage,
        sui_yield_storage,
        handle_principal_vector(sft_principal_vector, principal_value, ctx),
        handle_yield_vector(sft_yield_vector, yield_value, ctx),
        maturity,
        validator_address,
        unstake_payload,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

  public fun burn_sui_principal(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_principal_storage: &mut SuiPrincipalStorage,
    sft_principal_vector: vector<SemiFungibleToken<SUI_PRINCIPAL>>,
    principal_value: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    ctx: &mut TxContext,
  ) {
    public_transfer_coin(
      pool::burn_sui_principal(
        wrapper,
        storage,
        sui_principal_storage,
        handle_principal_vector(sft_principal_vector, principal_value, ctx),
        validator_address,
        unstake_payload,
        ctx
      ),
      tx_context::sender(ctx))
  }

  public fun claim_yield(
    wrapper: &mut SuiSystemState,
    storage: &mut PoolStorage,
    sui_yield_storage: &mut SuiYieldStorage,
    sft_yield_vector: vector<SuiYield>,
    yield_value: u64,
    validator_address: address,
    unstake_payload: vector<UnstakePayload>,
    maturity: u64,
    ctx: &mut TxContext,
  ) {
    let (yield, coin_sui) = pool::claim_yield(
      wrapper,
      storage,
      sui_yield_storage,
      handle_yield_vector(sft_yield_vector, yield_value, ctx),
      validator_address,
      unstake_payload,
      maturity,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_yield(yield, sender);
    public_transfer_coin(coin_sui, sender);
  }
}