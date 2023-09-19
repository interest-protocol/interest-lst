// Helper Functions to calculate iSUIP and iSUIY prices in Sui
// Bond Price = C* (1-(1+r)^n/r) + Par Value / (1+r)^n
module interest_lst::bond_math {

  use sui::tx_context::{Self, TxContext};

  use interest_lst::math::pow;
  use interest_lst:sui_yield::{Self as y, SuiYield};
  use interest_lst::semi_fungible_token::SemiFungibleToken;
  use interest_lst::sui_principal::{Self as p, SUI_PRINCIPAL};

  const ONE: u64 = 1_000_000_000; // 1 

  // Zero-Coupon Price = Par Value / (1+r)^n
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
    ((((value as u256) * (ONE as u256)) / d) as u64)
  }

  // Par Value = Zero-Coupon Price * (1 + r)^n
  public fun get_isuip_amount(sui_amount: u64, r: u64, n: u64): u64 {
    (((sui_amount as u256) * pow(((ONE + r) as u256), (n as u256))) / (ONE as u256) as u64)
  }

  public fun get_isuiy_price(asset: &SuiYield, coupon_rate: u64, r: u64, ctx: &mut TxContext): u64 {
    // The maturity epoch
    let maturity = (y::slot(asset) as u64);
    // Par value of the bond in Sui
    let value = y::value(asset);
    // How many epochs until maturity
    let n = maturity - tx_context::epoch(ctx);
    let one = (ONE as u256);    

    // coupon rate * par value
    let coupon = ((coupon_rate as u256) * (value as u256)) / one; 
    // (1+r)^-n
    let x = one * one / pow(((ONE + r) as u256), (n as u256));

    // C * ((1 - (1 +r)^-n) / r)
    (((coupon * (((one - x) * one) / (r as u256))) / one) as u64)
  }

  public fun get_isuiy_amount(sui_amount: u64, r: u64, n: u64): u64 {
    let one = (ONE as u256);   

    // (1+r)^-n
    let x = one * one / pow(((ONE + r) as u256), (n as u256));
    // 1-(1+r)^n / r
    let d = ((one - x) * one) / (r as u256);
    
    ((((sui_amount as u256) * one) / d) as u64)
  }
}