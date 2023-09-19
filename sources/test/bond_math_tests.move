#[test_only]
module interest_lst::bond_math_tests {

  use sui::test_utils::assert_eq;
  use sui::test_scenario::{Self as test, next_tx, ctx};

  use interest_lst::test_utils::{people, scenario}; 

  #[test]
  fun test_get_isuip_price() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    next_tx(test, alice);
    {};
    test::end(scenario); 
  }
}