#[test_only]
module interest_lsd::review_tests {
  use std::vector;
  use std::string;

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::table;

  use sui_system::sui_system::{SuiSystemState};
  use sui_system::governance_test_utils::{advance_epoch, create_validator_for_testing, create_sui_system_state_for_testing};

  use interest_lsd::pool;
  use interest_lsd::admin::{Self, AdminCap};
  use interest_lsd::review::{Self, Reviews};
  use interest_lsd::sui_yield::{Self, SuiYield};
  use interest_lsd::test_utils::{people, scenario}; 

  const MYSTEN_LABS: address = @0x4;
  const FIGMENT: address = @0x5;
  const COINBASE_CLOUD: address = @0x6;
  const SPARTA: address = @0x7;
  const JOSE: address = @0x8;

  #[test]
  fun test_crud_review() {
    let scenario = scenario();
    let test = &mut scenario;
    
    init_test(test);
    let (alice, _) = people();

    // create review
    next_tx(test, alice); {
      let reviews = test::take_shared<Reviews>(test);
      // verify set up storage
      let (total_reviews, total_reputation, validators, max_top, _, top, cooldown, nft_epochs) = review::read_storage(&reviews);
      assert_eq(total_reviews, 0);
      assert_eq(total_reputation, 0);
      assert_eq(table::length(validators), 0);
      assert_eq(max_top, 0);
      assert_eq(vector::length(top), 0);
      assert_eq(cooldown, 0);
      assert_eq(table::length(nft_epochs), 0);

      let (threshold_addr, threshold_rep) = review::read_threshold(&reviews);
      assert_eq(threshold_addr, @0x0);
      assert_eq(threshold_rep, 0);

      let admin_cap = test::take_from_sender<AdminCap>(test);
      // we need to "create" the top list by setting a length
      review::set_max_top_len(&admin_cap, &mut reviews, 2);

      let system = test::take_shared<SuiSystemState>(test);
      // get a nft to create reviews, reputation = 10 sqrt(100SUI)
      let nft = sui_yield::mint_for_testing(100_000_000_000, 0, test::ctx(test));
      
      review::create(&mut system, &mut reviews, &nft, MYSTEN_LABS, true, string::utf8(b"random"), test::ctx(test));
      
      let (total_reviews, total_reputation, validators, max_top, _, top, cooldown, nft_epochs) = review::read_storage(&reviews);
      assert_eq(total_reviews, 1);
      assert_eq(total_reputation, 10);
      assert_eq(table::length(validators), 1);
      assert_eq(max_top, 2);
      assert_eq(vector::length(top), 1);
      assert_eq(cooldown, 0);
      assert_eq(table::length(nft_epochs), 1);

      let (threshold_addr, threshold_rep) = review::read_threshold(&reviews);
      assert_eq(threshold_addr, @0x0);
      assert_eq(threshold_rep, 0);

      let (vote, reputation, comment) = review::get_review_data(&reviews, alice, MYSTEN_LABS);
      assert_eq(vote, true);
      assert_eq(reputation, 10);
      assert_eq(comment, string::utf8(b"random"));

      let (upvotes, downvotes, reputation) = review::get_validator_data(&reviews, MYSTEN_LABS);
      assert_eq(upvotes, 1);
      assert_eq(downvotes, 0);
      assert_eq(reputation, 10);

      let (validator_addr, reputation) = review::read_top_validator_by_index(&reviews, 0);
      assert_eq(validator_addr, MYSTEN_LABS);
      assert_eq(reputation, 10);

      sui::transfer::public_transfer(nft, alice);
      test::return_to_sender(test, admin_cap);
      test::return_shared(reviews);
      test::return_shared(system);
    }; 

    // UPDATE REVIEW (comment only)
    advance_epoch(test);
    next_tx(test, alice); {
      let reviews = test::take_shared<Reviews>(test);      
      let nft = test::take_from_sender<SuiYield>(test);

      review::update(&mut reviews, &nft, MYSTEN_LABS, true, string::utf8(b"different"), test::ctx(test));
      
      let (total_reviews, total_reputation, validators, max_top, _, top, cooldown, nft_epochs) = review::read_storage(&reviews);
      assert_eq(total_reviews, 1);
      assert_eq(total_reputation, 10);
      assert_eq(table::length(validators), 1);
      assert_eq(max_top, 2);
      assert_eq(vector::length(top), 1);
      assert_eq(cooldown, 0);
      assert_eq(table::length(nft_epochs), 1);

      let (threshold_addr, threshold_rep) = review::read_threshold(&reviews);
      assert_eq(threshold_addr, @0x0);
      assert_eq(threshold_rep, 0);

      let (vote, reputation, comment) = review::get_review_data(&reviews, alice, MYSTEN_LABS);
      assert_eq(vote, true);
      assert_eq(reputation, 10);
      assert_eq(comment, string::utf8(b"different"));

      let (upvotes, downvotes, reputation) = review::get_validator_data(&reviews, MYSTEN_LABS);
      assert_eq(upvotes, 1);
      assert_eq(downvotes, 0);
      assert_eq(reputation, 10);

      let (validator_addr, reputation) = review::read_top_validator_by_index(&reviews, 0);
      assert_eq(validator_addr, MYSTEN_LABS);
      assert_eq(reputation, 10);

      test::return_to_sender(test, nft);
      test::return_shared(reviews);
    }; 

    // UPDATE REVIEW (with vote)
    advance_epoch(test);
    next_tx(test, alice); {
      let reviews = test::take_shared<Reviews>(test);      
      let nft = test::take_from_sender<SuiYield>(test);

      review::update(&mut reviews, &nft, MYSTEN_LABS, false, string::utf8(b"another"), test::ctx(test));
      
      let (total_reviews, total_reputation, validators, max_top, _, top, cooldown, nft_epochs) = review::read_storage(&reviews);
      assert_eq(total_reviews, 1);
      assert_eq(total_reputation, 0);
      assert_eq(table::length(validators), 1);
      assert_eq(max_top, 2);
      assert_eq(vector::length(top), 1);
      assert_eq(cooldown, 0);
      assert_eq(table::length(nft_epochs), 1);

      let (threshold_addr, threshold_rep) = review::read_threshold(&reviews);
      assert_eq(threshold_addr, @0x0);
      assert_eq(threshold_rep, 0);

      let (vote, reputation, comment) = review::get_review_data(&reviews, alice, MYSTEN_LABS);
      assert_eq(vote, false);
      assert_eq(reputation, 10);
      assert_eq(comment, string::utf8(b"another"));

      let (upvotes, downvotes, reputation) = review::get_validator_data(&reviews, MYSTEN_LABS);
      assert_eq(upvotes, 0);
      assert_eq(downvotes, 1);
      assert_eq(reputation, 0);

      let (validator_addr, reputation) = review::read_top_validator_by_index(&reviews, 0);
      assert_eq(validator_addr, MYSTEN_LABS);
      assert_eq(reputation, 0);

      test::return_to_sender(test, nft);
      test::return_shared(reviews);
    }; 

    // DELETE REVIEW
    advance_epoch(test);
    next_tx(test, alice); {
      let reviews = test::take_shared<Reviews>(test);      

      review::delete(&mut reviews, MYSTEN_LABS, test::ctx(test));
      
      let (total_reviews, total_reputation, validators, max_top, _, top, cooldown, nft_epochs) = review::read_storage(&reviews);
      assert_eq(total_reviews, 0);
      assert_eq(total_reputation, 10);
      assert_eq(table::length(validators), 1);
      assert_eq(max_top, 2);
      assert_eq(vector::length(top), 1);
      assert_eq(cooldown, 0);
      assert_eq(table::length(nft_epochs), 1);

      let (threshold_addr, threshold_rep) = review::read_threshold(&reviews);
      assert_eq(threshold_addr, @0x0);
      assert_eq(threshold_rep, 0);

      let (upvotes, downvotes, reputation) = review::get_validator_data(&reviews, MYSTEN_LABS);
      assert_eq(upvotes, 0);
      assert_eq(downvotes, 0);
      assert_eq(reputation, 10); // see if this is a problem
      //we get 10 instead of 0 because when a user review negatively a validator with 0 reputation
      // and then delete this review we are adding 10 to counter the previous -10 
      // which didn't happen because it was already at 0

      let (validator_addr, reputation) = review::read_top_validator_by_index(&reviews, 0);
      assert_eq(validator_addr, MYSTEN_LABS);
      assert_eq(reputation, 10); // see if this is a problem
      //we get 10 instead of 0 because when a user review negatively a validator with 0 reputation
      // and then delete this review we are adding 10 to counter the previous -10 
      // which didn't happen because it was already at 0

      test::return_shared(reviews);
    }; 


    test::end(scenario); 
  }

  // Set up Functions

  fun init_test(test: &mut Scenario) {
    set_up_sui_system_state();

    let (alice, _) = people();
    next_tx(test, alice);
    {
      review::init_for_testing(ctx(test));
      admin::init_for_testing(ctx(test));
      pool::init_for_testing(ctx(test));
      sui_yield::init_for_testing(ctx(test));
    };
    advance_epoch(test);
  }

  fun set_up_sui_system_state() {
    let scenario = test::begin(@0x0);
    let test = &mut scenario;
    let ctx = test::ctx(test);

    let validators = vector[
            create_validator_for_testing(MYSTEN_LABS, 100, ctx),
            create_validator_for_testing(FIGMENT, 200, ctx),
            create_validator_for_testing(COINBASE_CLOUD, 300, ctx),
            create_validator_for_testing(SPARTA, 400, ctx),
    ];
    create_sui_system_state_for_testing(validators, 1000, 0, ctx);
    test::end(scenario);
  }
}