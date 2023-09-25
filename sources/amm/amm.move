// An AMM to trade Sui Principal and Sui Yield using Bond Price = C * (1-(1+r)^n/r) + Par Value / (1+r)^n 
// The pool grows over time as iSUIP approaches maturity and iSUI accrues rewards
/*
* The following swaps are supported
* iSUi <> iSUIP
* iSui <> iSUIY
*/
module interest_lst::amm {
  use sui::transfer;
  use sui::event::emit;
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::vec_set::{Self, VecSet};
  use sui::balance::{Self, Balance};
  use sui::tx_context::{Self, TxContext};
  
  use sui_system::sui_system::SuiSystemState;

  use interest_lst::errors;
  use interest_lst::constants;
  use interest_lst::bond_math;
  use interest_lst::isui::ISUI;
  use interest_lst::admin::AdminCap;
  use interest_lst::sui_principal::{SUI_PRINCIPAL};
  use interest_lst::fixed_point64::{Self, FixedPoint64};
  use interest_lst::pool::{Self as lst, PoolStorage as LSTStorage};
  use interest_lst::semi_fungible_balance::{Self as sfb,SFTBalance};
  use interest_lst::lp_token::{Self as lp_token, LP_TOKEN, LPTokenStorage};
  use interest_lst::semi_fungible_token::{Self as sft, SemiFungibleToken as SFT};

  struct Registry has key {
    id: UID,
    pools: VecSet<u64>,
    initial_r: FixedPoint64
  }

  struct Pool has key {
    id: UID,
    isui_balance: Balance<ISUI>,
    principal_balance: SFTBalance<SUI_PRINCIPAL>,
    k: u128, // This value must be equal or higher after Swaps
    r: FixedPoint64,
    fee_isui_balance: Balance<ISUI>,
    fee_principal_balance: SFTBalance<SUI_PRINCIPAL>,
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

  struct WithdrawFees has copy, drop {
    pool_id: ID,
    fee_isui: u64,
    fee_principal: u64
  }

  fun init(ctx: &mut TxContext) {
    transfer::share_object(
      Registry {
        id: object::new(ctx),
        pools: vec_set::empty(),
        // 2.87% based AAVE USDC Supply Yield
        initial_r: fixed_point64::create_from_rational(287,  10000 * 365)
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
    // pool exists already
    assert!(!vec_set::contains(&registry.pools, &maturity), errors::amm_pool_already_exists());

    // Calculate how much iSui is worth in principal
    let principal_optimal_value = bond_math::get_zero_coupon_bond_amount(
      lst::get_exchange_rate_isui_to_sui(wrapper, lst_storage, coin::value(&coin_isui), ctx),
      registry.initial_r,
      maturity - tx_context::epoch(ctx)
    );
    
    // User must provide the exact value
    // Epoch is every 24 hours so it is easy to get the exact value
    assert!(sft::value(&principal) == principal_optimal_value, errors::amm_not_enough_principal());
    
    // Mint and Burn a minimum LP amount to avoid zero division
    transfer::public_transfer(lp_token::mint(lp_storage, maturity, 100, ctx), @0x0);

    // Create the pool
    let pool = Pool {
      id: object::new(ctx),
      isui_balance: coin::into_balance(coin_isui),
      principal_balance: sft::into_balance(principal),
      k: (principal_optimal_value as u128) * 2,
      r: registry.initial_r,
      maturity,
      fee: 0,
      fee_isui_balance: balance::zero(),
      fee_principal_balance: sfb::zero((maturity as u256))
    };

    // Log to the network
    emit(CreatePool { 
      pool_id: object::id(&pool), 
      k: pool.k, 
      r: fixed_point64::round(pool.r), 
      maturity 
    });

    // Share the object
    transfer::share_object(pool);

    // register the pool
    vec_set::insert(&mut registry.pools, maturity);

    // Mint LP tokens to the caller
    lp_token::mint(lp_storage, maturity, principal_optimal_value, ctx)
  }

   // ** Admin Functions

   public fun update_r(_: &AdminCap, pool: &mut Pool, r_numerator: u64) {
    // Cannot be higher than 20%
    assert!(2000 >= r_numerator, errors::amm_invalid_r());

    let old_r = pool.r;

    pool.r = fixed_point64::create_from_rational(436,  10000 * 365);

    emit(UpdateR { pool_id: 
      object::id(pool), 
      old_r: fixed_point64::round(old_r), 
      new_r: fixed_point64::round(pool.r) 
      }
    );
   }

   public fun update_fee(_: &AdminCap, pool: &mut Pool, fee: u128) {
    assert!((constants::five_percent() as u128) >= fee, errors::amm_invalid_fee());
    emit(UpdateFee { pool_id: object::id(pool), old_fee: pool.fee, new_fee: fee });
    pool.fee = fee;
   }

   public fun withdraw_fees(_: &AdminCap, pool: &mut Pool, ctx: &mut TxContext): (Coin<ISUI>, SFT<SUI_PRINCIPAL>) {
    emit(WithdrawFees { pool_id: object::id(pool), fee_isui: balance::value(&pool.fee_isui_balance), fee_principal: sfb::value(&pool.fee_principal_balance) });

    (
     coin::from_balance(balance::withdraw_all(&mut pool.fee_isui_balance), ctx),
     sft::from_balance(sfb::withdraw_all(&mut pool.fee_principal_balance), ctx)
    )
   }
}