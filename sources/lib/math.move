// Fixed Point Math using 1e9
// It should give enough precision as Sui Coins have 9 decimals
module interest_lst::math {

  use interest_lst::constants::{one_sui_value};
  
  const EZeroDivision: u64 = 0;

  public fun fmul(x: u128, y: u128): u128 {
     (mul_div(x, y, (one_sui_value() as u128)) as u128)
  }

  public fun fdiv(x: u128, y: u128): u128 {
    assert!(y != 0, EZeroDivision);
    (mul_div(x, (one_sui_value() as u128), y) as u128)
  }

  /// https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1
  /// calculate x * y /z with as little loss of precision as possible and avoid overflow
  public fun mul_div(x: u128, y: u128, z: u128): u128 {
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

    // CREDITS to STARCOIN https://github.com/starcoinorg/starcoin-framework/blob/main/sources/Math.move
    spec mul_div {
      pragma opaque = true;
      include MulDivAbortsIf;
      aborts_if [abstract] false;
      ensures [abstract] result == spec_mul_div();
    }

    spec schema MulDivAbortsIf {
      x: u128;
      y: u128;
      z: u128;
      aborts_if y != z && x > z && z == 0;
      aborts_if y != z && x > z && z!=0 && x/z*y > MAX_U128;
      aborts_if y != z && x <= z && z == 0;
      //a * b overflow
      aborts_if y != z && x <= z && x / z * (x % z) > MAX_U128;
      //a * b * z overflow
      aborts_if y != z && x <= z && x / z * (x % z) * z > MAX_U128;
      //a * d overflow
      aborts_if y != z && x <= z && x / z * (y % z) > MAX_U128;
      //a * b * z + a * d overflow
      aborts_if y != z && x <= z && x / z * (x % z) * z + x / z * (y % z) > MAX_U128;
      //b * c overflow
      aborts_if y != z && x <= z && x % z * (y / z) > MAX_U128;
      //b * d overflow
      aborts_if y != z && x <= z && x % z * (y % z) > MAX_U128;
      //b * d / z overflow
      aborts_if y != z && x <= z && x % z * (y % z) / z > MAX_U128;
      //a * b * z + a * d + b * c overflow
      aborts_if y != z && x <= z && x / z * (x % z) * z + x / z * (y % z) + x % z * (y / z) > MAX_U128;
      //a * b * z + a * d + b * c + b * d / z overflow
      aborts_if y != z && x <= z && x / z * (x % z) * z + x / z * (y % z) + x % z * (y / z) + x % z * (y % z) / z > MAX_U128;
    }

    spec fun spec_mul_div(): u128;
}