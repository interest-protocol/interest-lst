// An AMM to trade Sui Principal and Sui Yield using Bond Price = C * (1-(1+r)^n/r) + Par Value / (1+r)^n 
// The pool grows over time as iSUIP approaches maturity and iSUI accrues rewards
/*
* The following swaps are supported
* iSUi <> iSUIP
* iSui <> iSUIY
*/
module amm::amm {
  use sui::transfer;
  use sui::event::emit;
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::vec_map::{Self, VecMap};
  use sui::balance::{Balance};
  use sui::tx_context::{Self, TxContext};
  
  use sui_system::sui_system::SuiSystemState;

  use access::admin::AdminCap;

  use interest_framework::constants;
  use interest_framework::fixed_point64::{Self, FixedPoint64};
  use interest_framework::semi_fungible_balance::{Self as sfb,SFTBalance};
  use interest_framework::semi_fungible_token::{Self as sft, SemiFungibleToken as SFT};

  use interest_tokens::isui::ISUI;
  use interest_tokens::sui_principal::SUI_PRINCIPAL;
  
  use interest_lst::pool::{Self as lst, PoolStorage as LSTStorage};

  use amm::utils;
  use amm::bond_math;
  use amm::lp_token::{Self, LP_TOKEN, LPTokenStorage};

  // Errors
  const EOldMaturity: u64 = 0;
  const EPoolAlreadyExists: u64 = 1;
  const ENotEnoughPrincipal: u64 = 2;
  const EInvalidFee: u64 = 3;

  struct Registry has key {
    id: UID,
    pools: VecMap<u64, ID>, // Maturity => Pool ID
    initial_r: FixedPoint64
  }

  struct Pool has key {
    id: UID,
    sy_balance: Balance<ISUI>,
    principal_balance: SFTBalance<SUI_PRINCIPAL>,
    k: u128, // This value must be equal or higher after Swaps
    initial_r: FixedPoint64,
    future_r: FixedPoint64,
    initial_a_time: u64,
    future_a_time: u64,
    fee_balance: SFTBalance<LP_TOKEN>,
    maturity: u64,
    fee: u128
  }

  // Events
  struct CreatePool has copy, drop {
    pool_id: ID,
    k: u128,
    r: u128,
    maturity: u64
  }

  struct UpdateInitialR has copy, drop {
    old_r: u128,
    new_r: u128
  }

  struct UpdateR has copy, drop {
    pool_id: ID,
    old_r: u128,
    new_r: u128
  }

  struct UpdateFee has copy, drop {
    pool_id: ID,
    old_fee: u128,
    new_fee: u128
  }

  struct WithdrawFeeBalance has copy, drop {
    pool_id: ID,
    amount: u64,
    maturity: u64
  }

  fun init(ctx: &mut TxContext) {
    transfer::share_object(
      Registry {
        id: object::new(ctx),
        pools: vec_map::empty(),
        // 2.87% based AAVE USDC Supply Yield
        initial_r: utils::create_r(constants::initial_r_numerator())
      }
    );
  }

  public fun create_pool(
    registry: &mut Registry,
    wrapper: &mut SuiSystemState,
    lst_storage: &mut LSTStorage, 
    lp_storage: &mut LPTokenStorage,
    coin_isui: Coin<ISUI>,
    principal: SFT<SUI_PRINCIPAL>,
    ctx: &mut TxContext
  ): SFT<LP_TOKEN> {
    let maturity = (sft::slot(&principal) as u64);

    // No point to create a new pool for matured bonds
    assert!(tx_context::epoch(ctx) > maturity, EOldMaturity);
    // pool exists already
    assert!(!vec_map::contains(&registry.pools, &maturity), EPoolAlreadyExists);

    // Calculate how much iSui is worth in principal
    let principal_optimal_value = bond_math::get_zero_coupon_bond_amount(
      lst::get_exchange_rate_isui_to_sui(wrapper, lst_storage, coin::value(&coin_isui), ctx),
      registry.initial_r,
      utils::get_safe_n(maturity, ctx)
    );
    
    // User must provide the exact value
    // Epoch is every 24 hours so it is easy to get the exact value
    assert!(sft::value(&principal) == principal_optimal_value, ENotEnoughPrincipal);
    
    // Mint and Burn a minimum LP amount to avoid zero division
    transfer::public_transfer(lp_token::mint(lp_storage, maturity, constants::min_amm_lp_token_value(), ctx), @0x0);

    // Create the pool
    let pool = Pool {
      id: object::new(ctx),
      sy_balance: coin::into_balance(coin_isui),
      principal_balance: sft::into_balance(principal),
      k: (principal_optimal_value as u128) * 2,
      initial_r: registry.initial_r,
      future_r: registry.initial_r,
      initial_a_time: 0,
      future_a_time: 0,
      maturity,
      fee: 0,
      fee_balance: sfb::zero((maturity as u256))
    };

    let pool_id = object::id(&pool);

    // Log to the network
    emit(CreatePool { 
      pool_id, 
      k: pool.k, 
      r: fixed_point64::round(registry.initial_r), 
      maturity 
    });

    // Share the object
    transfer::share_object(pool);

    // register the pool
    vec_map::insert(&mut registry.pools, maturity, pool_id);

    // Mint LP tokens to the caller
    lp_token::mint(lp_storage, maturity, principal_optimal_value, ctx)
  }

  // ** Admin Functions

  public fun update_initial_r(_: &AdminCap, registry: &mut Registry, r_numerator: u128) {
    let old_r = registry.initial_r;

    registry.initial_r = utils::create_r(r_numerator);

    emit(UpdateInitialR {
      old_r: fixed_point64::round(old_r), 
      new_r: fixed_point64::round(registry.initial_r) 
      }
    );
   }

   public fun update_r(_: &AdminCap, pool: &mut Pool, r_numerator: u128) {
    // let old_r = pool.r;

    // pool.r = utils::create_r(r_numerator);

    // emit(UpdateR { pool_id: 
    //   object::id(pool), 
    //   old_r: fixed_point64::round(old_r), 
    //   new_r: fixed_point64::round(pool.r) 
    //   }
    // );
   }

   public fun update_fee(_: &AdminCap, pool: &mut Pool, fee: u128) {
    assert!((constants::five_percent() as u128) >= fee, EInvalidFee);
    emit(UpdateFee { pool_id: object::id(pool), old_fee: pool.fee, new_fee: fee });
    pool.fee = fee;
   }

   public fun withdraw_fee_balance(_: &AdminCap, pool: &mut Pool, ctx: &mut TxContext): SFT<LP_TOKEN> {
    emit(WithdrawFeeBalance { pool_id: object::id(pool), 
    amount: sfb::value(&pool.fee_balance), maturity: pool.maturity });

    sft::from_balance(sfb::withdraw_all(&mut pool.fee_balance), ctx)
   }
}