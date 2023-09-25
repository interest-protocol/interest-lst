// An AMM to trade Sui Principal and Sui Yield using Bond Price = C * (1-(1+r)^n/r) + Par Value / (1+r)^n
module interest_lst::amm {
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::balance::{Balance};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::vec_set::{Self, VecSet};
  use sui::event::emit;

  use sui_system::sui_system::SuiSystemState;

  use interest_lst::errors;
  use interest_lst::admin::AdminCap;
  use interest_lst::semi_fungible_balance::{SFTBalance};
  use interest_lst::semi_fungible_token::{Self as sft, SemiFungibleToken as SFT};
  use interest_lst::isui::ISUI;
  use interest_lst::sui_principal::{SUI_PRINCIPAL};
  use interest_lst::sui_lp_token::{Self as lp_token, SUI_LP_TOKEN, LPTokenStorage};
  use interest_lst::fixed_point64::{Self, FixedPoint64};
  use interest_lst::bond_math;
  use interest_lst::pool::{Self as lst, PoolStorage as LSTStorage};

  struct Registry has key {
    id: UID,
    pools: VecSet<u64>
  }

  struct Pool has key {
    id: UID,
    isui_balance: Balance<ISUI>,
    principal_balance: SFTBalance<SUI_PRINCIPAL>,
    k: u128,
    r: FixedPoint64,
    admin: address,
    maturity: u64
  }

  // Events
  struct CreatePool has copy, drop {
    pool_id: ID,
    k: u128,
    r: u128,
    maturity: u64
  }

  fun init(ctx: &mut TxContext) {
    transfer::share_object(
      Registry {
        id: object::new(ctx),
        pools: vec_set::empty()
      }
    );
  }

  public fun create_pool(
    _: &AdminCap,
    registry: &mut Registry,
    wrapper: &mut SuiSystemState,
    lst_storage: &mut LSTStorage, 
    lp_storage: &mut LPTokenStorage,
    r: FixedPoint64,
    coin_isui: Coin<ISUI>,
    principal: SFT<SUI_PRINCIPAL>,
    ctx: &mut TxContext
  ): SFT<SUI_LP_TOKEN> {
    let maturity = (sft::slot(&principal) as u64);
    // pool exists already
    assert!(!vec_set::contains(&registry.pools, &maturity), errors::amm_pool_already_exists());

    let coin_isui_value = coin::value(&coin_isui);

    // Calculate how much iSui is worth in principal
    let principal_optimal_value = bond_math::get_zero_coupon_bond_amount(
      lst::get_exchange_rate_isui_to_sui(wrapper, lst_storage, coin_isui_value, ctx),
      r,
      maturity - tx_context::epoch(ctx)
    );
    
    // User must provide the exact value
    // Epoch is every 24 hours so it is easy to get the exact value
    assert!(sft::value(&principal) == principal_optimal_value, errors::amm_not_enough_principal());
    
    // Mint and Burn a minimum LP amount to avoid zero division
    transfer::public_transfer(lp_token::mint(lp_storage, maturity, 100, ctx), @0x0);

    let pool = Pool {
      id: object::new(ctx),
      isui_balance: coin::into_balance(coin_isui),
      principal_balance: sft::into_balance(principal),
      k: (principal_optimal_value as u128) * 2,
      r,
      admin: @admin,
      maturity
    };

    emit(CreatePool { pool_id: object::id(&pool), k: pool.k, r: fixed_point64::get_raw_value(r), maturity });

    transfer::share_object(pool);
    
    // register the pool
    vec_set::insert(&mut registry.pools, maturity);

    lp_token::mint(lp_storage, maturity, principal_optimal_value, ctx)
  }
}