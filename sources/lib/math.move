// Fixed Point Math using 1e9
// It should give enough precision as Sui Coins have 9 decimals
module interest_lst::math {

  const SCALAR: u256 = 1_000_000_000; // 1e9 - Sui accuracy
  const U128_MAX: u128 = 340282366920938463463374607431768211455;
  
  const EZeroDivision: u64 = 0;

  public fun fmul(x: u128, y: u128): u128 {
     (mul_div((x as u256), (y as u256), SCALAR) as u128)
  }

  public fun fdiv(x: u128, y: u128): u128 {
    assert!(y != 0, EZeroDivision);
    (mul_div((x as u256), SCALAR, (y as u256)) as u128)
  }

  /// https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1
  /// calculate x * y /z with as little loss of precision as possible and avoid overflow
  public fun mul_div(x: u256, y: u256, z: u256): u256{
      if (y == z) {
          return x
      };
      if (x == z) {
          return y
      };
      let a = x / z;
      let b = x % z;
      //x = a * z + b;
      let c = y / z;
      let d = y % z;
      //y = c * z + d;
      a * c * z + a * d + b * c + b * d / z
    }
}