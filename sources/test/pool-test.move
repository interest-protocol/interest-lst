#[test_only]
module interest_lsd::pools_test {
  use std::option;

  use sui::linked_table;
  use sui::object_table;
  use sui::coin::{Self, burn_for_testing as burn};
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::sui::{SUI};

  use sui_system::sui_system::{SuiSystemState};
  use sui_system::governance_test_utils::{set_up_sui_system_state, advance_epoch, assert_validator_non_self_stake_amounts};
  use sui_system::staking_pool;
  
  use interest_lsd::pool::{Self, PoolStorage};
  use interest_lsd::isui::{Self, InterestISuiStorage};
  use interest_lsd::isui_pc;
  use interest_lsd::isui_yc;
  use interest_lsd::rebase;
  use interest_lsd::fee_utils::{read_fee};
  use interest_lsd::test_utils::{people, scenario, mint, add_decimals}; 

  const MYSTEN_LABS: address = @0x4;
  const FIGMENT: address = @0x5;
  const COINBASE_CLOUD: address = @0x6;
  const INITIAL_SUI_AMOUNT: u64 = 600000000000000000;
  const JOSE: address = @0x7;

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
  fun test_first_mint_isui() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    set_up_sui_system_state(vector[MYSTEN_LABS, FIGMENT, COINBASE_CLOUD]);

    let (alice, _) = people();

    // An epoch of 0 will throw our logic
    advance_epoch(test);
    next_tx(test, alice);
    {
      let pool_storage = test::take_shared<PoolStorage>(test);

      let (pool_rebase, last_epoch, validators_table, total_principal, fee, dao_coin) = pool::read_pool_storage(&pool_storage);

      let (base, kink, jump) = read_fee(fee);

      // Nothing deposited on the pool
      assert_eq(rebase::base(pool_rebase), 0);
      assert_eq(rebase::elastic(pool_rebase), 0);
      // There has been no calls to {updatePool}
      assert_eq(last_epoch, 0);
      // No validator has been registered
      assert_eq(linked_table::length(validators_table), 0);
      assert_eq(total_principal, 0);
      assert_eq(base, 0);
      assert_eq(kink, 0);
      assert_eq(jump, 0);
      assert_eq(coin::value(dao_coin), 0);

      // First deposit should update the data correctly
      let wrapper = test::take_shared<SuiSystemState>(test);
      let interest_isui_storage = test::take_shared<InterestISuiStorage>(test);

      let coin_isui = pool::mint_isui(
        &mut wrapper,
        &mut pool_storage,
        &mut interest_isui_storage,
        mint<SUI>(1000, 9, ctx(test)),
        MYSTEN_LABS,
        ctx(test)
      );

      assert_eq(burn(coin_isui), add_decimals(1000, 9));

      let (pool_rebase, last_epoch, validators_table, total_principal, _, dao_coin) = pool::read_pool_storage(&pool_storage);

      // The first deposit gets all shares
      assert_eq(rebase::base(pool_rebase), add_decimals(1000, 9));
      assert_eq(rebase::elastic(pool_rebase), add_decimals(1000, 9));
      // We update to the prev epoch which is 0
      assert_eq(last_epoch, 0);
      // We registered the validator
      assert_eq(linked_table::length(validators_table), 1);
      // Update the total_principal
      assert_eq(total_principal, add_decimals(1000, 9));
      // No fees
      assert_eq(coin::value(dao_coin), 0);

      let mysten_labs_data = linked_table::borrow(validators_table, MYSTEN_LABS);

      let (staked_sui_table, last_staked_sui, staking_pool_id, last_rewards, total_principal) = pool::read_validator_data(mysten_labs_data);
      
      // We cached the sui
      assert_eq(object_table::length(staked_sui_table), 0);
      assert_eq(staking_pool::staked_sui_amount(option::borrow(last_staked_sui)), add_decimals(1000, 9));
      assert_eq(staking_pool::pool_id(option::borrow(last_staked_sui)), staking_pool_id);
      assert_eq(last_rewards, 0);
      assert_eq(total_principal ,add_decimals(1000, 9));

      test::return_shared(interest_isui_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };    

    // Test if we deposited to the right validator
    advance_epoch(test);
    next_tx(test, @0x0);
    {
      assert_validator_non_self_stake_amounts(vector[MYSTEN_LABS, FIGMENT, COINBASE_CLOUD], vector[add_decimals(1000, 9), 0, 0], test);
    };

    test::end(scenario); 
  }

  #[test]
  fun test_mint_isui_multiple_stakes_one_validator() {

  }
}
