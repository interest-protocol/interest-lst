/*
 TODO TEST Error cases, Corner Cases and invariant cases.
 We only tested the core functionality
*/
#[test_only]
module interest_lst::lst_tests {
  use std::option;

  use sui::balance;
  use sui::sui::SUI;
  use sui::linked_table;
  use sui::test_utils::assert_eq;
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{mint_for_testing, burn_for_testing as burn, TreasuryCap};

  use sui_system::staking_pool;
  use sui_system::sui_system::SuiSystemState;
  use sui_system::governance_test_utils::{
    create_sui_system_state_for_testing, 
    create_validator_for_testing, 
    advance_epoch, 
    assert_validator_total_stake_amounts, 
    advance_epoch_with_reward_amounts
  };
  
  use suitears::fund;
  use suitears::semi_fungible_token::{Self as sft, SftTreasuryCap};

  use yield::yield::{Self, YieldCap};

  use interest_lst::isui::{Self, ISUI};
  use interest_lst::fee_utils::read_fee;
  use interest_lst::interest_lst::{Self as lst, InterestLST};
  use interest_lst::isui_yield::{Self, ISUI_YIELD};
  use interest_lst::isui_principal::{Self, ISUI_PRINCIPAL};
  use interest_lst::unstake_algorithms::default_unstake_algorithm;
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
      let storage = test::take_shared<InterestLST>(test);

      let (lst_fund, last_epoch, validators_table, total_principal, fee, dao_balance, _) = lst::read_state(&mut storage);

      let (base, kink, jump) = read_fee(fee);

      // Nothing deposited on the pool
      assert_eq(fund::shares(lst_fund), 0);
      assert_eq(fund::underlying(lst_fund), 0);
      // There has been no calls to {updatePool}
      assert_eq(last_epoch, 0);
      // No validator has been registered
      assert_eq(linked_table::length(validators_table), 0);
      assert_eq(total_principal, 0);
      assert_eq(base, 0);
      assert_eq(kink, 0);
      assert_eq(jump, 0);
      assert_eq(balance::value(dao_balance), 0);

      // First deposit should update the data correctly
      let sui_state = test::take_shared<SuiSystemState>(test);

      let coin_isui = lst::mint_isui(
        &mut sui_state,
        &mut storage,
        mint<SUI>(1000, 9, ctx(test)),
        MYSTEN_LABS,
        ctx(test)
      );

      assert_eq(burn(coin_isui), add_decimals(1000, 9));

      let (lst_fund, last_epoch, validators_table, total_principal, _, dao_balance, _) = lst::read_state(&mut storage);

      // The first deposit gets all shares
      assert_eq(fund::shares(lst_fund), add_decimals(1000, 9));
      assert_eq(fund::underlying(lst_fund), add_decimals(1000, 9));
      // We update to the prev epoch which is 0
      assert_eq(last_epoch, 0);
      // We registered the validator
      assert_eq(linked_table::length(validators_table), 1);
      // Update the total_principal
      assert_eq(total_principal, add_decimals(1000, 9));
      // No fees
      assert_eq(balance::value(dao_balance), 0);

      let (staked_sui_table, total_principal) = lst::read_validator_data(&mut storage, MYSTEN_LABS);
      
      // We cached the sui
      assert_eq(linked_table::length(staked_sui_table), 1);
      // StakedSUi become active after the epoch they were created
      // We deposited on Epoch 1, so it is activated and saved in the table at epoch 2
      assert_eq(staking_pool::staked_sui_amount(linked_table::borrow(staked_sui_table, 2)), add_decimals(1000, 9));
      assert_eq(total_principal ,add_decimals(1000, 9));

      test::return_shared(sui_state);
      test::return_shared(storage);
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
      let storage = test::take_shared<InterestLST>(test);

      let (lst_fund, last_epoch, _, total_principal, _, _, _) = lst::read_state(&mut storage);


      assert_eq(last_epoch, 4);
      assert_eq(total_principal, add_decimals(40, 9));
      // 30 (deposit from Bob and alice) * 10 (Jose Deposit) / ~35.7 (Pool principal + rewards)
      assert_eq(fund::shares(lst_fund), 38387096774);
      // 40 principal (Jose + Alice + Bob) + Rewards
      assert_eq(fund::underlying(lst_fund), 45769230769);

     let (staked_sui_table,  validator_total_principal) = lst::read_validator_data(&mut storage, MYSTEN_LABS);

      assert_eq(validator_total_principal, total_principal);

      let front_staked_sui = linked_table::borrow(staked_sui_table, *option::borrow(linked_table::front(staked_sui_table)));
      let jose_staked_sui = linked_table::borrow(staked_sui_table, *option::borrow(linked_table::next(staked_sui_table, staking_pool::stake_activation_epoch(front_staked_sui))));
      // Bob and Alice Deposit joint together
      assert_eq(staking_pool::staked_sui_amount(front_staked_sui), add_decimals(30, 9));
      // Jose Deposit
      assert_eq(staking_pool::staked_sui_amount(jose_staked_sui), add_decimals(10, 9));

      test::return_shared(storage);
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
      let sui_state = test::take_shared<SuiSystemState>(test);
      let storage = test::take_shared<InterestLST>(test);

      lst::update_pool(&mut sui_state, &mut storage, ctx(test));

      let (lst_fund, _, validator_data_table, total_principal, _, _, _) = lst::read_state(&mut storage);

      assert_eq(fund::shares(lst_fund), 61258881888);
      assert_eq(fund::underlying(lst_fund), 89958076487);
      assert_eq(total_principal, add_decimals(70, 9));
      // Three diff validators
      assert_eq(linked_table::length(validator_data_table), 3);

      // Mysten Labs Data
      let (staked_sui_table,  validator_total_principal) = lst::read_validator_data(&mut storage, MYSTEN_LABS);
      assert_eq(validator_total_principal, add_decimals(40, 9));
      assert_eq(linked_table::length(staked_sui_table), 2);

      // Coinbase Cloud Data
      let (staked_sui_table,  validator_total_principal) = lst::read_validator_data(&mut storage, COINBASE_CLOUD);
      assert_eq(validator_total_principal, add_decimals(20, 9));
      assert_eq(linked_table::length(staked_sui_table), 2);

      // Figment Data
      let (staked_sui_table,  validator_total_principal) = lst::read_validator_data(&mut storage, FIGMENT);
      assert_eq(validator_total_principal, add_decimals(10, 9));
      assert_eq(linked_table::length(staked_sui_table), 1);

      test::return_shared(sui_state);
      test::return_shared(storage);
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
      let storage = test::take_shared<InterestLST>(test);
      let sui_state = test::take_shared<SuiSystemState>(test);

      lst::update_pool(&mut sui_state, &mut storage, ctx(test));

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

      let isui_unstake_amount = fund::to_shares(lst_fund, add_decimals(10, 9), true);

      let old_underlying = fund::underlying(lst_fund);
      let old_shares = fund::shares(lst_fund);

      let unstake_payload = default_unstake_algorithm(&mut storage, add_decimals(10, 9), ctx(test));

      // Unstakes the correct amount
      assert_eq(
        burn(
        lst::burn_isui(
          &mut sui_state, 
          &mut storage,
          mint_for_testing<ISUI>(isui_unstake_amount, ctx(test)),
          COINBASE_CLOUD,
          unstake_payload,
          ctx(test)
          )
        ),
      add_decimals(10, 9)
      );

      let (lst_fund, _, _, total_principal, _, _, _) = lst::read_state(&mut storage);

      // Pool is correctly updated after burn
      assert_eq(fund::underlying(lst_fund), old_underlying - add_decimals(10, 9));
      assert_eq(fund::shares(lst_fund), old_shares - isui_unstake_amount);

      // Correctly updates the total principal
      // it is 60 Sui + Rewards
      assert_eq(total_principal, 60000000000);

      // Coinbase Cloud Data
      let (staked_sui_table,  validator_total_principal) = lst::read_validator_data(&mut storage, FIGMENT);
      assert_eq(validator_total_principal, add_decimals(10, 9));
      // We removed One Staked Sui
      assert_eq(linked_table::length(staked_sui_table), 1);

      // Mysten Labs Data
      let (staked_sui_table,  validator_total_principal) = lst::read_validator_data(&mut storage, MYSTEN_LABS);
      // Principal - The rewards are in Coinbase Cloud
      assert_eq(validator_total_principal, 30000000000);
      assert_eq(linked_table::length(staked_sui_table), 2);

      test::return_shared(sui_state);
      test::return_shared(storage);
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
      let storage = test::take_shared<InterestLST>(test);
      let sui_state = test::take_shared<SuiSystemState>(test);

      let (residue, coupon) = lst::mint_stripped_bond(
        &mut sui_state,
        &mut storage,
        mint<SUI>(10, 9, ctx(test)),
        MYSTEN_LABS,
        10,
        ctx(test)
      );

      let (lst_fund, _, validator_data_table, total_principal, _, _, _) = lst::read_state(&mut storage);

      assert_eq(total_principal, add_decimals(10, 9));
      assert_eq(fund::underlying(lst_fund), add_decimals(10, 9));
      assert_eq(fund::shares(lst_fund), add_decimals(10, 9));

      // Mysten Labs Data
      assert_eq(linked_table::length(validator_data_table), 1);
      let (staked_sui_table,  validator_total_principal) = lst::read_validator_data(&mut storage, MYSTEN_LABS);
      // Principal + Rewards as we stake the left over here
      assert_eq(validator_total_principal, add_decimals(10, 9));
      assert_eq(linked_table::length(staked_sui_table), 1);

      let (_, residue_value) = sft::burn_for_testing(residue);

      assert_eq(residue_value, add_decimals(10, 9));

      // ISUI_YC has the same minting logic as ISUI
      let (shares, principal, rewards_paid) = yield::read_data(&coupon);
      assert_eq(principal, add_decimals(10, 9));
      assert_eq(shares, add_decimals(10, 9));
      assert_eq(rewards_paid, 0);

      yield::burn_for_testing( coupon);

      test::return_shared(sui_state);
      test::return_shared(storage);
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
      let storage = test::take_shared<InterestLST>(test);
      let sui_state = test::take_shared<SuiSystemState>(test);
      
      lst::update_pool(&mut sui_state, &mut storage, ctx(test));

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

   

      let principal_amount = add_decimals(10, 9);

      let old_underlying = fund::underlying(lst_fund);
      let old_shares = fund::shares(lst_fund);

      let (_, principal_cap, yield_cap) = lst::borrow_mut_caps(&mut storage);
 

      let coupon = yield::mint_with_supply_for_testing(
        yield_cap,
        20, 
        principal_amount, 
        principal_amount, 
        ctx(test)
      );

      let residue = sft::mint(
        principal_cap,
        20,
        principal_amount,
        ctx(test)
      );

      let yield_amount = lst::get_pending_yield(
        &mut sui_state,
        &mut storage,
        &coupon,
        20,
        ctx(test)
      );

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

      let shares_burned = fund::to_shares(lst_fund, principal_amount + yield_amount, false);

      let unstake_payload = default_unstake_algorithm(&mut storage, principal_amount + yield_amount, ctx(test));

      assert_eq(burn(lst::call_bond(
        &mut sui_state,
        &mut storage,
        residue,
        coupon,
        30,
         MYSTEN_LABS,
         unstake_payload,
        ctx(test)
      )), principal_amount + yield_amount);

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

      assert_eq(old_shares, fund::shares(lst_fund) + shares_burned);
      assert_eq(old_underlying, fund::underlying(lst_fund) + principal_amount + yield_amount);

      test::return_shared(sui_state);
      test::return_shared(storage);
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
      let storage = test::take_shared<InterestLST>(test);
      let sui_state = test::take_shared<SuiSystemState>(test);

      lst::update_pool(&mut sui_state, &mut storage, ctx(test));
      let (_, principal_cap, _) = lst::borrow_mut_caps(&mut storage);

      let residue = sft::mint(principal_cap, 1, add_decimals(10, 9), ctx(test));

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

      let old_shares = fund::shares(lst_fund);
      let old_underlying = fund::underlying(lst_fund);
      let removed_shares = fund::to_shares(lst_fund, add_decimals(10, 9), false);

      let unstake_payload = default_unstake_algorithm(&mut storage, add_decimals(10, 9), ctx(test));

      let coin_sui = lst::burn_sui_principal(
        &mut sui_state,
        &mut storage,
        residue,
        MYSTEN_LABS,
        unstake_payload,
        ctx(test)
      );

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

      assert_eq(burn(coin_sui), add_decimals(10, 9));
      assert_eq(fund::shares(lst_fund), old_shares - removed_shares);
      assert_eq(fund::underlying(lst_fund), old_underlying - add_decimals(10, 9));

      test::return_shared(sui_state);
      test::return_shared(storage); 
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
      let storage = test::take_shared<InterestLST>(test);
      let sui_state = test::take_shared<SuiSystemState>(test);

      lst::update_pool(&mut sui_state, &mut storage, ctx(test));

      let value = add_decimals(10, 9);

      let coupon = yield::mint_for_testing<ISUI_YIELD>(
         10, value, value, 800000, ctx(test)
      );

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

      let old_shares = fund::shares(lst_fund);
      let old_underlying = fund::underlying(lst_fund);
      let yield_earned = fund::to_underlying(lst_fund, value, false) - 800000 - value;
      let shares_burned = fund::to_shares(lst_fund, yield_earned, false);

      let unstake_paylaod = default_unstake_algorithm(&mut storage, yield_earned, ctx(test));

      let (coupon_returned, rewards) = lst::claim_yield(
        &mut sui_state,
        &mut storage,
        coupon,
        MYSTEN_LABS, 
        unstake_paylaod,
        99,
        ctx(test)
      );

      let (lst_fund, _, _, _, _, _, _) = lst::read_state(&mut storage);

      assert_eq(burn(rewards), yield_earned);
      assert_eq(yield::shares(&coupon_returned), value);
      assert_eq(yield::value(&coupon_returned), value);
      assert_eq(yield::rewards_paid(&coupon_returned), yield_earned + 800000);
      assert_eq(fund::shares(lst_fund), old_shares - shares_burned);
      assert_eq(fund::underlying(lst_fund), old_underlying  - yield_earned);
      
      yield::burn_for_testing(coupon_returned);

      test::return_shared(sui_state);
      test::return_shared(storage); 
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
      isui_principal::init_for_testing(ctx(test));
      isui_yield::init_for_testing(ctx(test));
      lst::init_for_testing(ctx(test));
    };

    next_tx(test, alice);
    {
      let isui_cap = test::take_from_sender<TreasuryCap<ISUI>>(test);
      let principal_cap = test::take_from_sender<SftTreasuryCap<ISUI_PRINCIPAL>>(test);
      let yield_cap = test::take_from_sender<YieldCap<ISUI_YIELD>>(test);
      let storage = test::take_shared<InterestLST>(test);

      lst::create_genesis_state(&mut storage, isui_cap, principal_cap, yield_cap, ctx(test));

      test::return_shared(storage);
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
      let sui_state = test::take_shared<SuiSystemState>(test);
      let storage = test::take_shared<InterestLST>(test);

      burn(lst::mint_isui(
        &mut sui_state,
        &mut storage,
        mint<SUI>(amount, 9, ctx(test)),
        validator,
        ctx(test)
      ));

      test::return_shared(sui_state);
      test::return_shared(storage);
    };
  }
}
