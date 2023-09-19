// Helper Functions to calculate iSUIP and iSUIY prices in Sui
// Bond Price = C * (1-(1+r)^n/r) + Par Value / (1+r)^n
module interest_lst::bond_math {

  use std::debug::print;
  use sui::tx_context::{Self, TxContext};

  use interest_lst::sui_yield::{Self as y, SuiYield};
  use interest_lst::semi_fungible_token::SemiFungibleToken;
  use interest_lst::sui_principal::{Self as p, SUI_PRINCIPAL};
  use interest_lst::fixed_point64::{Self, FixedPoint64};
  use interest_lst::math_fixed64::pow;

  const ONE: u64 = 1_000_000_000; // 1 
  const COMPOUNDING_PERIODS: u256 = 2; // Compound semi-annually


  const EZeroDivision: u64 = 0;

  // Zero-Coupon Price = Par Value / (1+r)^n
  /*
  * @param asset The Zero Coupon Bond
  * @param r The discount rate (YTM) per epoch with 3 decimal houses
  */
  public fun get_isuip_price(asset: &SemiFungibleToken<SUI_PRINCIPAL>, r: FixedPoint64, ctx: &mut TxContext): u64 {
    // Par Value of the bond in Sui
    let value = p::value(asset);
    // Maturity Epoch of the bond
    let maturity = (p::slot(asset) as u64);
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
  * @param sui_amount The desired sui amount one wishes to buy
  * @param r The risk-free rate per epoch 
  * @param n The number of epochs until maturity 
  * @return u64 Amount of naked bond sui_amount can buy
  */
  public fun get_isuip_amount(sui_amount: u64, r: FixedPoint64, n: u64): u64 {
    // If the Bond has matured, it can be redeemed by its par value
    if (n == 0) return sui_amount;

    pow(
      fixed_point64::add(
        fixed_point64::create_from_rational(1,1), 
          r
        ), 
      n
    );
    
    (fixed_point64::multiply_u128((sui_amount as u128), pow(
      fixed_point64::add(
        fixed_point64::create_from_rational(1,1), 
          r
        ), 
      n
    )) as u64)
  }

  // // Price = C * (1-(1+r)^n) / r
  // /*
  // * @param asset The Coupon of a bond
  // * @param coupon_rate The coupon rate per epoch
  // * @param r The risk-free rate per epoch 
  // */
  // public fun get_isuiy_price(asset: &SuiYield, coupon_rate: u64, r: u64, ctx: &mut TxContext): u64 {
  //   // The maturity epoch
  //   let maturity = (y::slot(asset) as u64);
  //   // Par value of the bond this Coupon was stripped from in Sui
  //   let value = y::value(asset);

  //   let current_epoch = tx_context::epoch(ctx);

  //   // If the Bond has matured, the coupon is worth 0. All payments have been made
  //   if (current_epoch >= maturity) return 0;

  //   // How many epochs until maturity
  //   let n = maturity - current_epoch;

  //   // coupon rate * par value
  //   let coupon = fmul((coupon_rate as u256), (value as u256)); 
  //   // (1+r)^-n
  //   let x = fdiv((ONE as u256), pow(((ONE + r) as u256), (n as u256)));

  //   // C * ((1 - (1 +r)^-n) / r)
  //   (fmul(coupon, fdiv((ONE as u256) - x, (r as u256))) as u64)
  // }

  // // Par Value = (Price / ((1-(1+r)^n) / r)) / coupon rate
  // /*
  // * @param asset The Coupon of a bond
  // * @param coupon_rate The coupon rate per epoch
  // * @param r The risk-free rate per epoch 
  // */
  // public fun get_isuiy_amount(sui_amount: u64, coupon_rate: u64, r: u64, n: u64): u64 {
  //   // If the Bond has matured, the coupon is worth 0. There is no point to buy it.
  //   if (n == 0) return 0;

  //   let one = (ONE as u256);   

  //   // (1+r)^-n
  //   let x = fdiv(one, pow(((ONE + r) as u256), (n as u256)));
  //   // 1-(1+r)^n / r
  //   let d = fdiv((one - x), (r as u256));
    
  //   // (Price / ((1-(1+r)^n) / r)) / coupon rate
  //   (fdiv(fdiv((sui_amount as u256), d), (coupon_rate as u256)) as u64)
  // }

  // * Fixed Point Math operations to maintain 9 decimal houses

  fun fmul(x: u256, y: u256): u256 {
    (x * y) / (ONE as u256)
  }

  fun fdiv(x: u256, y: u256): u256 {
    assert!(y != 0, EZeroDivision);
    (x * (ONE as u256)) / y
  }

    // Calculate x to the power of n, where x and the result are fixed point numbers.
  fun pow_raw(x: u256, n: u128): u256 {
      let res: u256 = 1 << 64;
      while (n != 0) {
          if (n & 1 != 0) {
              res = (res * x) >> 64;
          };
          n = n >> 1;
          x = (x * x) >> 64;
      };
      res
  }
}