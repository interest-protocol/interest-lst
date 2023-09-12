/*
 TODO TEST Error cases, Corner Cases and invariant cases.
 We only tested the core functionality
*/
#[test_only]
module interest_lst::pool_tests {
  use std::option;

  use sui::linked_table;
  use sui::coin::{Self, mint_for_testing, burn_for_testing as burn};
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::sui::{SUI};

  use sui_system::sui_system::{SuiSystemState};
  use sui_system::governance_test_utils::{
    create_sui_system_state_for_testing, 
    create_validator_for_testing, 
    advance_epoch, 
    assert_validator_total_stake_amounts, 
    advance_epoch_with_reward_amounts
  };
  use sui_system::staking_pool;
  
  use interest_lst::pool::{Self, PoolStorage};
  use interest_lst::isui::{Self, ISUI, InterestSuiStorage};
  use interest_lst::sui_principal::{Self, SuiPrincipalStorage};
  use interest_lst::sui_yield::{Self, SuiYieldStorage};
  use interest_lst::rebase;
  use interest_lst::fee_utils::{read_fee};
  use interest_lst::test_utils::{people, scenario, mint, add_decimals}; 

  const MYSTEN_LABS: address = @0x4;
  const FIGMENT: address = @0x5;
  const COINBASE_CLOUD: address = @0x6;
  const SPARTA: address = @0x7;
  const JOSE: address = @0x8;

  #[test]
  fun test_first_mint_isui() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let pool_storage = test::take_shared<PoolStorage>(test);

      let (pool_rebase, last_epoch, validators_table, total_principal, fee, dao_coin, _) = pool::read_pool_storage(&pool_storage);

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
      let interest_sui_storage = test::take_shared<InterestSuiStorage>(test);

      let coin_isui = pool::mint_isui(
        &mut wrapper,
        &mut pool_storage,
        &mut interest_sui_storage,
        mint<SUI>(1000, 9, ctx(test)),
        MYSTEN_LABS,
        ctx(test)
      );

      assert_eq(burn(coin_isui), add_decimals(1000, 9));

      let (pool_rebase, last_epoch, validators_table, total_principal, _, dao_coin, _) = pool::read_pool_storage(&pool_storage);

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

      let (staked_sui_table,   total_principal) = pool::read_validator_data(mysten_labs_data);
      
      // We cached the sui
      assert_eq(linked_table::length(staked_sui_table), 1);
      // StakedSUi become active after the epoch they were created
      // We deposited on Epoch 1, so it is activated and saved in the table at epoch 2
      assert_eq(staking_pool::staked_sui_amount(linked_table::borrow(staked_sui_table, 2)), add_decimals(1000, 9));
      assert_eq(total_principal ,add_decimals(1000, 9));

      test::return_shared(interest_sui_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };    

    // Test if we deposited to the right validator
    advance_epoch(test);
    next_tx(test, @0x0);
    {
      assert_validator_total_stake_amounts(validator_addrs(), vector[add_decimals(1100, 9), add_decimals(200, 9), add_decimals(300, 9), add_decimals(400, 9)], test);
    };

    test::end(scenario); 
  }

  #[test]
  fun test_mint_isui_multiple_stakes_one_validator() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people();

    mint_isui(test, MYSTEN_LABS, alice, 20);
    mint_isui(test, MYSTEN_LABS,  bob, 10);

    // Active Staked Sui
    advance_epoch(test);
    // Pay Rewards
    advance_epoch_with_reward_amounts(0, 100, test);
    // Advance once more so our module registers in the next call
    advance_epoch(test);

    mint_isui(test, MYSTEN_LABS,  JOSE, 10);

    // Properly calculates rewards/ shares
    next_tx(test, alice); 
    {
      let pool_storage = test::take_shared<PoolStorage>(test);

      let (pool_rebase, last_epoch, validator_data_table, total_principal, _, _, _) = pool::read_pool_storage(&pool_storage);

      let validator_data = linked_table::borrow(validator_data_table, MYSTEN_LABS);

      let (staked_sui_table,  validator_total_principal) = pool::read_validator_data(validator_data);

      assert_eq(last_epoch, 3);
      assert_eq(total_principal, add_decimals(40, 9));
      // 30 (deposit from Bob and alice) * 10 (Jose Deposit) / ~35.7 (Pool principal + rewards)
      assert_eq(rebase::base(pool_rebase), 38387096774);
      // 40 principal (Jose + Alice + Bob) + Rewards
      assert_eq(rebase::elastic(pool_rebase), 45769230769);
      assert_eq(validator_total_principal, total_principal);

      let front_staked_sui = linked_table::borrow(staked_sui_table, *option::borrow(linked_table::front(staked_sui_table)));
      let jose_staked_sui = linked_table::borrow(staked_sui_table, *option::borrow(linked_table::next(staked_sui_table, staking_pool::stake_activation_epoch(front_staked_sui))));
      // Bob and Alice Deposit joint together
      assert_eq(staking_pool::staked_sui_amount(front_staked_sui), add_decimals(30, 9));
      // Jose Deposit
      assert_eq(staking_pool::staked_sui_amount(jose_staked_sui), add_decimals(10, 9));

      test::return_shared(pool_storage);
    };

    test::end(scenario); 
  }

  #[test]
  fun test_mint_isui_multiple_stakes_multiple_validators() {
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

    // Test that the validator data is updated correctly
    next_tx(test, alice); 
    {
      let wrapper = test::take_shared<SuiSystemState>(test);
      let pool_storage = test::take_shared<PoolStorage>(test);

      pool::update_pool(&mut wrapper, &mut pool_storage, ctx(test));

      let (pool_rebase, _, validator_data_table, total_principal, _, _, _) = pool::read_pool_storage(&pool_storage);

      assert_eq(rebase::base(pool_rebase), 65093317280);
      assert_eq(rebase::elastic(pool_rebase), 82583633555);
      assert_eq(total_principal, add_decimals(70, 9));
      // Three diff validators
      assert_eq(linked_table::length(validator_data_table), 3);

      // Mysten Labs Data
      let (staked_sui_table,  validator_total_principal) = pool::read_validator_data(linked_table::borrow(validator_data_table, MYSTEN_LABS));
      assert_eq(validator_total_principal, add_decimals(40, 9));
      assert_eq(linked_table::length(staked_sui_table), 2);

      // Coinbase Cloud Data
      let (staked_sui_table,  validator_total_principal) = pool::read_validator_data(linked_table::borrow(validator_data_table, COINBASE_CLOUD));
      assert_eq(validator_total_principal, add_decimals(20, 9));
      assert_eq(linked_table::length(staked_sui_table), 2);

      // Figment Data
      let (staked_sui_table,  validator_total_principal) = pool::read_validator_data(linked_table::borrow(validator_data_table, FIGMENT));
      assert_eq(validator_total_principal, add_decimals(10, 9));
      assert_eq(linked_table::length(staked_sui_table), 1);

      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };

    test::end(scenario); 
  }

  #[test]
  fun test_burn_isui() {
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

      let validator_payload = vector[
        pool::create_burn_validator_payload(COINBASE_CLOUD, 2, add_decimals(10, 9)),
        pool::create_burn_validator_payload(COINBASE_CLOUD, 5, add_decimals(1, 9))
      ];

      let isui_unstake_amount = rebase::to_base(pool_rebase, add_decimals(10, 9), true);

      let old_elastic = rebase::elastic(pool_rebase);
      let old_base = rebase::base(pool_rebase);

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

      let (pool_rebase, _, validator_data_table, total_principal, _, _, _) = pool::read_pool_storage(&pool_storage);

      // Pool is correctly updated after burn
      assert_eq(rebase::elastic(pool_rebase), old_elastic - add_decimals(10, 9));
      assert_eq(rebase::base(pool_rebase), old_base - isui_unstake_amount);

      // Correctly updates the total principal
      // it is 60 Sui + Rewards
      assert_eq(total_principal, 63026830133);

      // Coinbase Cloud Data
      let (staked_sui_table,  validator_total_principal) = pool::read_validator_data(linked_table::borrow(validator_data_table, COINBASE_CLOUD));
      assert_eq(validator_total_principal, add_decimals(9, 9));
      // We removed One Staked Sui
      assert_eq(linked_table::length(staked_sui_table), 1);

      // Mysten Labs Data
      let (staked_sui_table,  validator_total_principal) = pool::read_validator_data(linked_table::borrow(validator_data_table, MYSTEN_LABS));
      // Principal + Rewards as we stake the left over here
      assert_eq(validator_total_principal, 44026830133);
      assert_eq(linked_table::length(staked_sui_table), 3);

      test::return_shared(interest_sui_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };

    test::end(scenario); 
  }

  #[test]
  fun test_mint_stripped_bond() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people(); 
    
    // Mints Derivatives
    next_tx(test, alice); 
    {
      let pool_storage = test::take_shared<PoolStorage>(test);
      let wrapper = test::take_shared<SuiSystemState>(test);
      let interest_sui_storage = test::take_shared<InterestSuiStorage>(test);
      let interest_sui_principal_storage = test::take_shared<SuiPrincipalStorage>(test);
      let interest_sui_yield_Storage = test::take_shared<SuiYieldStorage>(test);

      let (residue, coupon) = pool::mint_stripped_bond(
        &mut wrapper,
        &mut pool_storage,
        &mut interest_sui_storage,
        &mut interest_sui_principal_storage,
        &mut interest_sui_yield_Storage,
        mint<SUI>(10, 9, ctx(test)),
        MYSTEN_LABS,
        10,
        ctx(test)
      );

      let (pool_rebase, _, validator_data_table, total_principal, _, _, _) = pool::read_pool_storage(&pool_storage);

      assert_eq(total_principal, add_decimals(10, 9));
      assert_eq(rebase::elastic(pool_rebase), add_decimals(10, 9));
      assert_eq(rebase::base(pool_rebase), add_decimals(10, 9));

      // Mysten Labs Data
      assert_eq(linked_table::length(validator_data_table), 1);
      let (staked_sui_table,  validator_total_principal) = pool::read_validator_data(linked_table::borrow(validator_data_table, MYSTEN_LABS));
      // Principal + Rewards as we stake the left over here
      assert_eq(validator_total_principal, add_decimals(10, 9));
      assert_eq(linked_table::length(staked_sui_table), 1);

      assert_eq(sui_principal::burn_destroy(&mut interest_sui_principal_storage, residue), add_decimals(10, 9));

      // ISUI_YC has the same minting logic as ISUI
      let (shares, principal, rewards_paid) = sui_yield::read_data(&coupon);
      assert_eq(principal, add_decimals(10, 9));
      assert_eq(shares, add_decimals(10, 9));
      assert_eq(rewards_paid, 0);

      sui_yield::burn_destroy(&mut interest_sui_yield_Storage, coupon);

      test::return_shared(interest_sui_yield_Storage);
      test::return_shared(interest_sui_principal_storage);
      test::return_shared(interest_sui_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };
    test::end(scenario);
  }

  #[test]
  fun test_call_bond() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people(); 

    // Add Rewards

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
    
    // ISUI_PC is always 1:1 with Sui
    // It gives no rewards
    next_tx(test, alice); 
    {
      let pool_storage = test::take_shared<PoolStorage>(test);
      let wrapper = test::take_shared<SuiSystemState>(test);
      let interest_sui_storage = test::take_shared<InterestSuiStorage>(test);
      let interest_sui_principal_storage = test::take_shared<SuiPrincipalStorage>(test);
      let interest_sui_yield_Storage = test::take_shared<SuiYieldStorage>(test);
      
      pool::update_pool(&mut wrapper, &mut pool_storage, ctx(test));

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

   

      let principal_amount = add_decimals(10, 9);

      let old_elastic = rebase::elastic(pool_rebase);
      let old_base = rebase::base(pool_rebase);
 

      let coupon = sui_yield::new_for_testing(
        &mut interest_sui_yield_Storage, 
        20, 
        principal_amount, 
        principal_amount, 
        0, 
        ctx(test)
      );

      let yield_amount = pool::get_pending_yield(
        &mut wrapper,
        &mut pool_storage,
        &coupon,
        20,
        ctx(test)
      );

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

      let shares_burned = rebase::to_base(pool_rebase, principal_amount + yield_amount, false);

      let validator_payload = vector[
        pool::create_burn_validator_payload(COINBASE_CLOUD, 2, add_decimals(10, 9)),
        pool::create_burn_validator_payload(COINBASE_CLOUD, 5, add_decimals(1, 9) + yield_amount)
      ];

      let residue = sui_principal::new_for_testing(
        &mut interest_sui_principal_storage,
        20,
        principal_amount,
        ctx(test)
      );

      assert_eq(burn(pool::call_bond(
        &mut wrapper,
        &mut pool_storage,
        &mut interest_sui_principal_storage,
        &mut interest_sui_yield_Storage,
        validator_payload,
        residue,
        coupon,
        MYSTEN_LABS,
        30,
        ctx(test)
      )), principal_amount + yield_amount);

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

      assert_eq(old_base, rebase::base(pool_rebase) + shares_burned);
      assert_eq(old_elastic, rebase::elastic(pool_rebase) + principal_amount + yield_amount);

      test::return_shared(interest_sui_storage);
      test::return_shared(interest_sui_yield_Storage);
      test::return_shared(interest_sui_principal_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage);
    };

    test::end(scenario); 
  }

  #[test]
  fun test_burn_sui_principal() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people(); 

    mint_isui(test, MYSTEN_LABS, alice, 30);
    mint_isui(test, COINBASE_CLOUD,  bob, 10);

    // Active Staked Sui
    advance_epoch_with_reward_amounts(0, 100, test);
    // Pay Rewards
    advance_epoch_with_reward_amounts(0, 100, test);
    // Advance once more so our module registers in the next call
    advance_epoch_with_reward_amounts(0, 100, test);
    
    // Test that ISUI_YC + ISUI_PC = ISUI
    next_tx(test, alice); 
    {
      let pool_storage = test::take_shared<PoolStorage>(test);
      let wrapper = test::take_shared<SuiSystemState>(test);
      let interest_sui_storage = test::take_shared<InterestSuiStorage>(test);
      let interest_sui_principal_storage = test::take_shared<SuiPrincipalStorage>(test);

      pool::update_pool(&mut wrapper, &mut pool_storage, ctx(test));

      let residue = sui_principal::new_for_testing(&mut interest_sui_principal_storage, 1, add_decimals(10, 9), ctx(test));

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

      let old_base = rebase::base(pool_rebase);
      let old_elastic = rebase::elastic(pool_rebase);
      let removed_shares = rebase::to_base(pool_rebase, add_decimals(10, 9), false);

      let coin_sui = pool::burn_sui_principal(
        &mut wrapper,
        &mut pool_storage,
        &mut interest_sui_principal_storage,
        vector[pool::create_burn_validator_payload(MYSTEN_LABS, 2, add_decimals(11, 9))],
        residue,
        MYSTEN_LABS,
        ctx(test)
      );

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

      assert_eq(burn(coin_sui), add_decimals(10, 9));
      assert_eq(rebase::base(pool_rebase), old_base - removed_shares);
      assert_eq(rebase::elastic(pool_rebase), old_elastic - add_decimals(10, 9));

      test::return_shared(interest_sui_principal_storage);
      test::return_shared(interest_sui_storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage); 
    };
    test::end(scenario);
}  

  #[test]
  fun test_claim_yield() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people(); 

    mint_isui(test, MYSTEN_LABS, alice, 30);
    mint_isui(test, COINBASE_CLOUD,  bob, 10);

    // Active Staked Sui
    advance_epoch_with_reward_amounts(0, 100, test);
    // Pay Rewards
    advance_epoch_with_reward_amounts(0, 100, test);
    // Advance once more so our module registers in the next call
    advance_epoch_with_reward_amounts(0, 100, test);

    // Mint Derivative
    next_tx(test, alice); 
    {
      let pool_storage = test::take_shared<PoolStorage>(test);
      let wrapper = test::take_shared<SuiSystemState>(test);
      let interest_sui_yield_Storage = test::take_shared<SuiYieldStorage>(test);

      pool::update_pool(&mut wrapper, &mut pool_storage, ctx(test));

      let value = add_decimals(10, 9);

      let coupon = sui_yield::new_for_testing(
        &mut interest_sui_yield_Storage, 10, value, value, 800000, ctx(test));

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

      let old_base = rebase::base(pool_rebase);
      let old_elastic = rebase::elastic(pool_rebase);
      let yield_earned = rebase::to_elastic(pool_rebase, value, false) - 800000 - value;
      let shares_burned = rebase::to_base(pool_rebase, yield_earned, false);

      let (coupon_returned, rewards) = pool::claim_yield(
        &mut wrapper,
        &mut pool_storage,
        vector[
          pool::create_burn_validator_payload(MYSTEN_LABS, 2, yield_earned + add_decimals(1, 9))],
        coupon,
        MYSTEN_LABS, 99,
        ctx(test)
      );

      let (pool_rebase, _, _, _, _, _, _) = pool::read_pool_storage(&pool_storage);

      assert_eq(burn(rewards), yield_earned);
      assert_eq(sui_yield::shares(&coupon_returned), value);
      assert_eq(sui_yield::value(&coupon_returned), value);
      assert_eq(sui_yield::rewards_paid(&coupon_returned), yield_earned + 800000);
      assert_eq(rebase::base(pool_rebase), old_base - shares_burned);
      assert_eq(rebase::elastic(pool_rebase), old_elastic - yield_earned);
      
      sui_yield::burn_destroy(&mut interest_sui_yield_Storage, coupon_returned);

      test::return_shared(interest_sui_yield_Storage);
      test::return_shared(wrapper);
      test::return_shared(pool_storage); 
    };
    test::end(scenario);
  }

  // Set up Functions

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

  fun validator_addrs() : vector<address> {
    vector[MYSTEN_LABS, FIGMENT, COINBASE_CLOUD, SPARTA]
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
