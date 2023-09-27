// Helper Functions to calculate the price of Zero Coupon Bonds and Coupons
// Bond Price = C * (1-(1+r)^n/r) + Par Value / (1+r)^n
module amm::bond_math {

  use sui::tx_context::{Self, TxContext};

  use interest_framework::constants::one_sui_value;
  use interest_framework::math_fixed64::pow;
  use interest_framework::math::{fmul, fdiv};
  use interest_framework::fixed_point64::{Self, FixedPoint64};
  use interest_framework::semi_fungible_token::{Self as sft, SemiFungibleToken};

  // Zero-Coupon Price = Par Value / (1+r)^n
  /*
  * @param asset The Zero Coupon Bond
  * @param r The discount rate (YTM) per epoch with 3 decimal houses
  */
  public fun get_zero_coupon_bond_price<T>(asset: &SemiFungibleToken<T>, r: FixedPoint64, ctx: &mut TxContext): u64 {
    // Par Value of the bond in Sui
    let value = sft::value(asset);
    // Maturity Epoch of the bond
    let maturity = (sft::slot(asset) as u64);
    // Current Epoch
    let current_epoch = tx_context::epoch(ctx);

    // If the bond has expired, it is valued at the Par Value
    if (current_epoch >= maturity) return value;

    // Find out how many more periods to compound
    let periods = maturity - current_epoch;
    
    // (1 + r)^n
    let d = pow(
      fixed_point64::add(
        fixed_point64::create_from_rational(1,1), 
          r
        ), 
      periods
    );

    // Par Value / (1+r)^n 
    (fixed_point64::divide_u128((value as u128), d) as u64)
  }

  // Par Value = Zero-Coupon Price * (1 + r)^n
  /*
  * @param amount The desired sui/eth/... amount one wishes to buy
  * @param r The risk-free rate per epoch 
  * @param n The number of epochs until maturity 
  * @return u64 Amount of naked bond sui_amount can buy
  */
  public fun get_zero_coupon_bond_amount(amount: u64, r: FixedPoint64, n: u64): u64 {
    // If the Bond has matured, it can be redeemed by its par value
    if (n == 0) return amount;
    
    (fixed_point64::multiply_u128((amount as u128), pow(
      fixed_point64::add(
        fixed_point64::create_from_rational(1,1), 
          r
        ), 
      n
    )) as u64)
  }

  // Price = C * (1-(1+r)^n) / r
  /*
  * @param asset The Coupon of a bond
  * @param coupon_rate The coupon rate per epoch
  * @param r The risk-free rate per epoch 
  */
  public fun get_coupon_price<T>(asset: &SemiFungibleToken<T>, coupon_rate: u64, r: FixedPoint64, ctx: &mut TxContext): u64 {
    // The maturity epoch
    let maturity = (sft::slot(asset) as u64);

    let current_epoch = tx_context::epoch(ctx);

    // If the Bond has matured, the coupon is worth 0. All payments have been made
    if (current_epoch >= maturity) return 0;

    // How many epochs until maturity
    let periods = maturity - current_epoch;

    // coupon rate * par value
    let coupon = (fmul((coupon_rate as u128), (sft::value(asset) as u128)) as u64); 

    let one = one_sui_value();

    // 1 - (1+r)^-n
    let x = one - (fixed_point64::divide_u128(
      (one as u128)
      , pow(fixed_point64::add(
        fixed_point64::create_from_rational(1,1), 
          r
        ), periods)
      ) 
    as u64);

    // C * ((1 - (1 +r)^-n) / r)
    (fmul((coupon as u128), (fixed_point64::divide_u128((x as u128), r) as u128)) as u64)
  }

  // Par Value = (Price / ((1-(1+r)^n) / r)) / coupon rate
  /*
  * @param amount of asset to convert to coupon
  * @param coupon_rate The coupon rate per epoch
  * @param r The risk-free rate per epoch 
  */
  public fun get_coupon_amount(amount: u64, coupon_rate: u64, r: FixedPoint64, n: u64): u64 {
    // If the Bond has matured, the coupon is worth 0. There is no point to buy it.
    if (n == 0) return 0;

    let one = one_sui_value();

    // 1 - (1+r)^-n
    let x = one - (fixed_point64::divide_u128(
      (one as u128)
      , pow(fixed_point64::add(
        fixed_point64::create_from_rational(1,1), 
          r
        ), n)
      ) 
    as u64);

    // 1-(1+r)^n / r
    let d = (fixed_point64::divide_u128((x as u128), r) as u128);
    
    // (Price / ((1-(1+r)^n) / r)) / coupon rate
    (fdiv(fdiv((amount as u128), d), (coupon_rate as u128)) as u64)
  }
}