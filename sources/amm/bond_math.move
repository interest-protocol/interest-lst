// Helper Functions to calculate iSUIP and iSUIY prices in Sui
// Bond Price = C* (1-(1+r)^n/r) + Par Value / (1+r)^n
module interest_lst::bond_math {

  use sui::tx_context::{Self, TxContext};

  use interest_lst::math::pow;
  use interest_lst::sui_yield::{Self as y, SuiYield};
  use interest_lst::semi_fungible_token::SemiFungibleToken;
  use interest_lst::sui_principal::{Self as p, SUI_PRINCIPAL};

  const ONE: u64 = 1_000_000_000; // 1 

  // Zero-Coupon Price = Par Value / (1+r)^n
  /*
  * @param asset The Zero Coupon Bond
  * @param r The risk-free rate per epoch
  */
  public fun get_isuip_price(asset: &SemiFungibleToken<SUI_PRINCIPAL>, r: u64, ctx: &mut TxContext): u64 {
    // The maturity epoch
    let maturity = (p::slot(asset) as u64);
    // Par value of the bond in Sui
    let value = p::value(asset);
    // How many epochs until maturity
    let n = maturity - tx_context::epoch(ctx);
    // (1 + r)^n
    // r is the low risk interest rate per epoch
    let d = pow(((ONE + r) as u256), (n as u256));

    // Par Value / (1 + r)^n
    (fdiv((value as u256), d) as u64)
  }

  // Par Value = Zero-Coupon Price * (1 + r)^n
  /*
  * @param asset The Zero Coupon Bond
  * @param r The risk-free rate per epoch 
  * @param n The number of epochs until maturity
  */
  public fun get_isuip_amount(sui_amount: u64, r: u64, n: u64): u64 {
    (fmul((sui_amount as u256), pow(((ONE + r) as u256), (n as u256))) as u64)
  }

  // Price = C * (1-(1+r)^n) / r
  /*
  * @param asset The Coupon of a bond
  * @param coupon_rate The coupon rate per epoch
  * @param r The risk-free rate per epoch 
  */
  public fun get_isuiy_price(asset: &SuiYield, coupon_rate: u64, r: u64, ctx: &mut TxContext): u64 {
    // The maturity epoch
    let maturity = (y::slot(asset) as u64);
    // Par value of the bond this Coupon was stripped from in Sui
    let value = y::value(asset);
    // How many epochs until maturity
    let n = maturity - tx_context::epoch(ctx);

    // coupon rate * par value
    let coupon = fmul((coupon_rate as u256), (value as u256)); 
    // (1+r)^-n
    let x = fdiv((ONE as u256), pow(((ONE + r) as u256), (n as u256)));

    // C * ((1 - (1 +r)^-n) / r)
    (fmul(coupon, fdiv((ONE as u256) - x, (r as u256))) as u64)
  }

  // Par Value = (Price / ((1-(1+r)^n) / r)) / coupon rate
  /*
  * @param asset The Coupon of a bond
  * @param coupon_rate The coupon rate per epoch
  * @param r The risk-free rate per epoch 
  */
  public fun get_isuiy_amount(sui_amount: u64, coupon_rate: u64, r: u64, n: u64): u64 {
    let one = (ONE as u256);   

    // (1+r)^-n
    let x = fdiv(one, pow(((ONE + r) as u256), (n as u256)));
    // 1-(1+r)^n / r
    let d = fmul((one - x), (r as u256));
    
    // (Price / ((1-(1+r)^n) / r)) / coupon rate
    (fdiv(fdiv((sui_amount as u256), d), (coupon_rate as u256)) as u64)
  }

  fun fmul(x: u256, y: u256): u256 {
    (x * y) / (ONE as u256)
  }

  fun fdiv(x: u256, y: u256): u256 {
    assert!(y != 0, 0);
    (x * (ONE as u256)) / y
  }
}