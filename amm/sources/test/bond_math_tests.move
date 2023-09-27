#[test_only]
module amm::bond_math_tests {

  use sui::test_utils::assert_eq;
  use sui::tx_context::{Self, TxContext};
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

  use interest_framework::fixed_point64;
  use interest_framework::test_utils::{people, scenario, add_decimals}; 
  use interest_framework::semi_fungible_token as sft;

  use interest_lst::sui_principal;
  
  use amm::bond_math::{
    get_coupon_price, 
    get_coupon_amount,
    get_zero_coupon_bond_price, 
    get_zero_coupon_bond_amount, 
  };

  struct Test has drop {}

  #[test]
  fun test_get_zero_coupon_bond_price() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {

      let sft = sui_principal::mint_for_testing(
        1510,
        add_decimals(1000, 9),
        ctx(test)
      );

      let ctx = make_ctx(50);
      // One epoch is roughly 1 day
      let r = fixed_point64::create_from_rational(40,  1000 * 365);

      assert_eq(
        get_zero_coupon_bond_price(
            &sft,
            r,
            &mut ctx
        ),
        852151259302 // ~850 SUI
      );

      // rounded to 0
      let ctx = make_ctx(1509);


      assert_eq(
        get_zero_coupon_bond_price(
            &sft,
            r,
            &mut ctx
        ),
        999890422967 // ~999 SUI
      );

      // very large bond
      // 1 Billion Sui bond
      let big_sft = sui_principal::mint_for_testing(
        1510,
        add_decimals(1_000_000_000, 9),
        ctx(test)
      );
      
      assert_eq(
        get_zero_coupon_bond_price(
            &big_sft,
            r,
            &mut ctx
        ),
        999890422967346044// ~999 SUI
      );

      sui_principal::burn_for_testing( sft);
      sui_principal::burn_for_testing( big_sft);

    };
    test::end(scenario); 
  }

  #[test]
  fun test_get_zero_coupon_bond_amount() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    // We use the values returned from {get_isuip_price}
    // So we can convert Sui to Sui Naked Bond and vice versa
    next_tx(test, alice);
    {
      assert_eq(
        get_zero_coupon_bond_amount(852151259302, fixed_point64::create_from_rational(40,  1000 * 365), 1510 - 50),
        add_decimals(1000, 9) - 1 // rounded down
      );

      assert_eq(
        get_zero_coupon_bond_amount(999890422967, fixed_point64::create_from_rational(40,  1000 * 365), 1510 - 1509),
        add_decimals(1000, 9) - 1 // rounded down
      );
    };
    test::end(scenario); 
  }

  #[test]
  fun test_get_isuiy_price() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    // We use the values returned from {get_isuip_price}
    // So we can convert Sui to Sui Naked Bond and vice versa
    next_tx(test, alice);
    {
      let sft = sft::mint_for_testing<Test>(
        1510,
        add_decimals(1000, 9),
        ctx(test)
      );

      assert_eq(
        get_coupon_price(
          &sft, 
          add_decimals(5, 7) / 365, 
          fixed_point64::create_from_rational(40,  1000 * 365),
          &mut make_ctx(50)
          ),
        184810519665 // ~ 184
      );

      // Worth less the closer it gets to maturity
      assert_eq(
        get_coupon_price(
          &sft, 
          add_decimals(5, 7) / 365, 
          fixed_point64::create_from_rational(40,  1000 * 365),
          &mut make_ctx(1200)
          ),
        41750176899 // ~ 40 
      );

      // Worth less the closer it gets to maturity
      assert_eq(
        get_coupon_price(
          &sft, 
          add_decimals(5, 7) / 365, 
          fixed_point64::create_from_rational(40,  1000 * 365),
          &mut make_ctx(1509)
          ),
        136972198 // ~ less than a dollar
      );

      sft::burn_for_testing( sft);

    };
    test::end(scenario); 
  }


    #[test]
  fun test_get_coupon_amount() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let r = fixed_point64::create_from_rational(40,  1000 * 365);
      
      assert_eq(
        get_coupon_amount(
          184810519665, 
          add_decimals(5, 7) / 365,
        r, 
        1510 - 50
        ),
        999999992699 // ~ 999 some precision loss due to fixed point math as it should be 1000. 
      );

      assert_eq(
        get_coupon_amount(
          41750176899, 
          add_decimals(5, 7) / 365,
        r, 
        1510 - 1200
        ),
        999999992699 // ~ 999 some precision loss due to fixed point math as it should be 1000. 
      );

      assert_eq(
        get_coupon_amount(
          136972198, 
          add_decimals(5, 7) / 365,
        r, 
        1510 - 1509
        ),
        999999992699 // ~ 999 some precision loss due to fixed point math as it should be 1000. 
      );
    };
    test::end(scenario); 
  }

  fun init_test(test: &mut Scenario) {

    let (alice, _) = people();

    next_tx(test, alice);
    {
      sui_principal::init_for_testing(ctx(test));
    };
  }

  fun make_ctx(epoch: u64): TxContext {
    tx_context::new(
        @0x0,
        x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
        epoch,
        0,
        0
      )
  }
}