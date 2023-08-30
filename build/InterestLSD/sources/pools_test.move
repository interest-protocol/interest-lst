#[test_only]
module interest_lsd::pools_test {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  
  use interest_lsd::pool;
  use interest_lsd::isui;
  use interest_lsd::isui_pc;
  use interest_lsd::isui_yc;
  use interest_lsd::test_utils::{people, scenario}; 

  public fun init_test(test: &mut Scenario) {
    let (alice, _) = people();

    next_tx(test, alice);
    {
      pool::init_for_testing(ctx(test));
      isui::init_for_testing(ctx(test));
      isui_pc::init_for_testing(ctx(test));
      isui_yc::init_for_testing(ctx(test));
    };
  }

  #[test]
  fun test_mint_isui() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      assert_eq(1, 1);
    };    
    test::end(scenario); 
  }
}