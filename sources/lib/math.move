module interest_lsd::math {

  const SCALAR: u256 = 1000000000000000000; // 1e18 - More accuracy

  const ERROR_ZERO_DIVISION: u64 = 0;

  public fun fmul(x: u256, y: u256): u256 {
    ((x * y ) / SCALAR)
  }

  public fun fdiv(x: u256, y: u256): u256 {
    assert!(y != 0, ERROR_ZERO_DIVISION);
    (x * SCALAR ) / y
  }
  
  public fun mul_div_u128(x: u128, y: u128, z: u128): u128 {
    assert!(z != 0, ERROR_ZERO_DIVISION);
    ((x as u256) * (y as u256) / (z as u256) as u128)
  }

  public fun scalar(): u256 {
    SCALAR
  }
}