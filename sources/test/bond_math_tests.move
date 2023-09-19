#[test_only]
module interest_lst::bond_math_tests {

  use sui::tx_context;
  use sui::test_utils::assert_eq;
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

  use interest_lst::fixed_point64;
  use interest_lst::bond_math::{get_isuip_price};
  use interest_lst::sui_yield::{Self, SuiYieldStorage};
  use interest_lst::sui_principal::{Self, SuiPrincipalStorage};
  use interest_lst::test_utils::{people, scenario, add_decimals}; 

  #[test]
  fun test_get_isuip_price() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let interest_sui_principal_storage = test::take_shared<SuiPrincipalStorage>(test);

      let sft = sui_principal::new_for_testing(
        &mut interest_sui_principal_storage,
        1510,
        add_decimals(1000, 9),
        ctx(test)
      );

      let ctx = tx_context::new(
        alice,
        x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
        50,
        0,
        0
      );
      // One epoch is roughly 1 day
      let r = fixed_point64::create_from_rational(40,  1000 * 365);
      let periods = 1510 - 50; // Compounded semi-annually

      assert_eq(
        get_isuip_price(
            &sft,
            r,
            &mut ctx
        ),
        852151259302 // ~850 SUI
      );

      // rounded to 0
      let ctx = tx_context::new(
        alice,
        x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
        1509,
        0,
        0
      );


      assert_eq(
        get_isuip_price(
            &sft,
            r,
            &mut ctx
        ),
        999890422967 // ~999 SUI
      );

      // very large bond
      // 1 Billion Sui bond
      let big_sft = sui_principal::new_for_testing(
        &mut interest_sui_principal_storage,
        1510,
        add_decimals(1_000_000_000, 9),
        ctx(test)
      );
      
      assert_eq(
        get_isuip_price(
            &big_sft,
            r,
            &mut ctx
        ),
        999890422967346044// ~999 SUI
      );

      sui_principal::burn_destroy(&mut interest_sui_principal_storage, sft);
      sui_principal::burn_destroy(&mut interest_sui_principal_storage, big_sft);

      test::return_shared(interest_sui_principal_storage);
    };
    test::end(scenario); 
  }

  fun init_test(test: &mut Scenario) {

    let (alice, _) = people();

    next_tx(test, alice);
    {
      sui_yield::init_for_testing(ctx(test));
      sui_principal::init_for_testing(ctx(test));
    };
  }
}