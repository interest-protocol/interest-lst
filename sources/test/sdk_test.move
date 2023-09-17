#[test_only]
module interest_lst::sdk_tests {

  use sui::coin::{mint_for_testing, burn_for_testing as burn};
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::sui::{SUI};

  use sui_system::sui_system::{SuiSystemState};
  use sui_system::governance_test_utils::{
    create_sui_system_state_for_testing, 
    create_validator_for_testing, 
    advance_epoch, 
    advance_epoch_with_reward_amounts
  };
  
  use interest_lst::sdk;
  use interest_lst::pool::{Self, PoolStorage};
  use interest_lst::isui::{Self, ISUI, InterestSuiStorage};
  use interest_lst::sui_principal;
  use interest_lst::sui_yield;
  use interest_lst::rebase;
  use interest_lst::test_utils::{people, scenario, mint, add_decimals}; 

  const MYSTEN_LABS: address = @0x4;
  const FIGMENT: address = @0x5;
  const COINBASE_CLOUD: address = @0x6;
  const SPARTA: address = @0x7;
  const JOSE: address = @0x8;

  #[test]
  fun test_create_burn_validator_payload() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people();

    mint_isui(test, MYSTEN_LABS, alice, 20);
    mint_isui(test, COINBASE_CLOUD,  bob, 10);

    // Active Staked Sui
    advance_epoch_with_reward_amounts(0, 100, test);
    // Pay Rewards
    advance_epoch_with_reward_amounts(0, 100, test);
    // Advance once more so our module registers in the next call
    advance_epoch_with_reward_amounts(0, 100, test);

    mint_isui(test, FIGMENT,  JOSE, 10);
    mint_isui(test, MYSTEN_LABS, alice, 20);
    mint_isui(test, COINBASE_CLOUD,  bob, 10);

    advance_epoch_with_reward_amounts(0, 100, test);
    advance_epoch_with_reward_amounts(0, 100, test);

    next_tx(test, alice);
    {
      let pool_storage = test::take_shared<PoolStorage>(test);
      let wrapper = test::take_shared<SuiSystemState>(test);
      let interest_sui_storage = test::take_shared<InterestSuiStorage>(test);

      pool::update_pool(&mut wrapper, &mut pool_storage, ctx(test));

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

      let validator_payload = sdk::create_burn_validator_payload(&pool_storage, add_decimals(10, 9), ctx(test));

      let isui_unstake_amount = rebase::to_base(pool_rebase, add_decimals(10, 9), true);

      // Unstakes the correct amount
      assert_eq(
        burn(
        pool::burn_isui(
          &mut wrapper, 
          &mut pool_storage,
          &mut interest_sui_storage,
          validator_payload,
          mint_for_testing<ISUI>(isui_unstake_amount, ctx(test)),
          MYSTEN_LABS,
          ctx(test)
          )
        ),
      add_decimals(10, 9)
      );

      let (_, _, _, total_principal, _, _, _) = pool::read_pool_storage(&pool_storage);

      // Correctly updates the total principal
      // it is 60 Sui + Rewards
      assert_eq(total_principal, 66752873563);

      test::return_shared(interest_sui_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };

    test::end(scenario); 
  }

    fun init_test(test: &mut Scenario) {
    set_up_sui_system_state();

    let (alice, _) = people();

    next_tx(test, alice);
    {
      isui::init_for_testing(ctx(test));
      sui_principal::init_for_testing(ctx(test));
      sui_yield::init_for_testing(ctx(test));
      pool::init_for_testing(ctx(test));
    };
    advance_epoch(test);
  }

  fun set_up_sui_system_state() {
    let scenario_val = test::begin(@0x0);
    let scenario = &mut scenario_val;
    let ctx = test::ctx(scenario);

    let validators = vector[
            create_validator_for_testing(MYSTEN_LABS, 100, ctx),
            create_validator_for_testing(FIGMENT, 200, ctx),
            create_validator_for_testing(COINBASE_CLOUD, 300, ctx),
            create_validator_for_testing(SPARTA, 400, ctx),
    ];
    create_sui_system_state_for_testing(validators, 1000, 0, ctx);
    test::end(scenario_val);
  }

  fun mint_isui(test: &mut Scenario, validator: address, sender: address, amount: u64) {
    next_tx(test, sender);
    {
      let pool_storage = test::take_shared<PoolStorage>(test);
      let wrapper = test::take_shared<SuiSystemState>(test);
      let interest_sui_storage = test::take_shared<InterestSuiStorage>(test);

      burn(pool::mint_isui(
        &mut wrapper,
        &mut pool_storage,
        &mut interest_sui_storage,
        mint<SUI>(amount, 9, ctx(test)),
        validator,
        ctx(test)
      ));

      test::return_shared(interest_sui_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };
  }
}