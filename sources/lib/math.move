// Fixed Point Math using 1e18 to mimic ERC20s 
// It should give enough precision as Sui Coins have 9 decimals
module interest_lst::math {

  const SCALAR: u256 = 1000000000000000000; // 1e18 - More accuracy

  const EZeroDivision: u64 = 0;

  public fun fmul(x: u256, y: u256): u256 {
    ((x * y ) / SCALAR)
  }

  public fun fdiv(x: u256, y: u256): u256 {
    assert!(y != 0, EZeroDivision);
    (x * SCALAR ) / y
  }

  public fun mul_div(x: u256, y: u256, z: u256): u256 {
    assert!(z != 0, EZeroDivision);
    (x * y) / z
  }

  public fun scalar(): u256 {
    SCALAR
  }
}