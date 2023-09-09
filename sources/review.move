/// This module provide an incentive mechanism to encourage users to improve decentralization
/// by getting informed on validators and rating them
/// The validator which gets the most points during a period will be whitelisted removing fees for stakers

module interest_lsd::review {
  use std::vector;
  use std::string::{Self, String};

  use sui::transfer;
  use sui::event::{emit};
  use sui::object::{Self, UID, ID};
  use sui::tx_context::{Self, TxContext};
  use sui::table::{Self, Table};
  use sui::math;

  use interest_lsd::sui_yield::{Self, SuiYield};
  use interest_lsd::admin::AdminCap;

  const ECannotReviewWithNft: u64 = 0;
  const EWrongStarNumber: u64 = 1;
  const ECommentTooLong: u64 = 2;
  const EAlreadyReviewed: u64 = 3;

  struct Review has store, drop {
    vote: bool,
    comment: String, // max 140 
  }

  struct Validator has store {
    upvotes: u64,
    downvotes: u64,
    reputation: u64, // + upvotes * stakes - downvotes * stakes
    reviews: Table<address, Review>, // user address
  }

  struct TopValidator has store, copy, drop {
    validator_address: address,
    reputation: u64,
  }

  // ** Shared

  struct Reviews has key {
    id: UID,
    total_reviews: u64,
    total_reputation: u64, // + upvotes * stakes - downvotes * stakes
    validators: Table<address, Validator>, // validator address
    max_top_len: u64, // how many validators will be whitelisted
    top_threshold: TopValidator, // the lowest validator's rating in the top 
    top_validators: vector<TopValidator>, // the validators that will be whitelisted
    cooldown_epochs: u64, // the number of epoch for which the nft cannot be used to review
    nft_review_epoch: Table<ID, u64>, // the epoch at which the nft was used to review
  }

  // ** Events

  struct Reviewed has copy, drop {
    author: address,
    validator: address,
    vote: bool,
    reputation: u64,
    comment: String,
  }


  fun init(ctx: &mut TxContext) {
    transfer::share_object(Reviews {
      id: object::new(ctx),
      total_reviews: 0,
      total_reputation: 0,
      validators: table::new(ctx),
      max_top_len: 0,
      top_threshold: TopValidator {validator_address: @0x0, reputation: 0},
      top_validators: vector::empty(),
      cooldown_epochs: 0,
      nft_review_epoch: table::new(ctx),
    })
  }

  // ** Reviews

  // @dev create a review and emit it
  // takes a YN nft to gate review access and limit their creation 
  /*
  * @param reviews: global storage 
  * @param nft: Sui Yield nft to verify cooldown
  * @param validator_address: the validator to review
  * @param vote: up/down vote
  * @param comment: maximum 140 characters explaining the choice
  
  */
  public fun create(
    reviews: &mut Reviews, 
    nft: &mut SuiYield, 
    validator_address: address,
    vote: bool,
    comment: String,
    ctx: &mut TxContext
  ) {
    // verify that nft isn't being cooled down
    let current_epoch = tx_context::epoch(ctx);
    let nft_id = object::uid_to_inner(sui_yield::uid(nft));
    let prev_epoch = table::borrow_mut(&mut reviews.nft_review_epoch, nft_id);

    assert!(current_epoch > *prev_epoch + reviews.cooldown_epochs, ECannotReviewWithNft);
    // update nft review epoch for cooldown
    *prev_epoch = current_epoch;
    
    // get validator to update his stats
    let validator = table::borrow_mut(&mut reviews.validators, validator_address);
    // check that the user didn't review it already
    assert!(table::contains(&validator.reviews, tx_context::sender(ctx)), EAlreadyReviewed);
    // store the previous reputation of the validator
    let prev_validator_reputation = validator.reputation;
    let reputation = get_reputation(nft);

    // update stats
    if (vote) { validator.upvotes = validator.upvotes + 1 } else { validator.downvotes = validator.downvotes - 1 };
    reviews.total_reputation = calculate_new_reputation(vote, reputation, reviews.total_reputation);
    validator.reputation = calculate_new_reputation(vote, reputation, prev_validator_reputation);
    reviews.total_reviews = reviews.total_reviews + 1;

    table::add(&mut validator.reviews, tx_context::sender(ctx), create_review(vote, comment));
    
    // update top validators and 
    update_validators(reviews, prev_validator_reputation, validator_address);

    emit(Reviewed { author: tx_context::sender(ctx), validator: validator_address, vote, reputation, comment });
  }

  // @dev update a review and emit it
  // takes a YN nft to gate review access and limit their creation 
  /*
  * @param reviews: global storage 
  * @param nft: Sui Yield nft to verify cooldown
  * @param validator_address: the validator to review
  * @param vote: up/down vote
  * @param comment: maximum 140 characters explaining the choice
  
  */
  public fun update(
    reviews: &mut Reviews, 
    nft: &mut SuiYield, 
    validator_address: address,
    vote: bool,
    comment: String,
    ctx: &mut TxContext
  ) {
    // verify that nft isn't being cooled down
    let current_epoch = tx_context::epoch(ctx);
    let nft_id = object::uid_to_inner(sui_yield::uid(nft));
    let prev_epoch = table::borrow_mut(&mut reviews.nft_review_epoch, nft_id);

    assert!(current_epoch > *prev_epoch + reviews.cooldown_epochs, ECannotReviewWithNft);
    // update nft review epoch for cooldown
    *prev_epoch = current_epoch;

    // get validator to update his stats
    let validator = table::borrow_mut(&mut reviews.validators, validator_address);
    // get previous review to remove it while adding the current one
    let prev_review = table::borrow_mut(&mut validator.reviews, tx_context::sender(ctx));
    // save the previous vote before updating the review 
    let prev_vote = prev_review.vote;
    // create a new review to replace the previous one
    *prev_review = create_review(vote, comment);

    let reputation = get_reputation(nft);
    // if the vote hasn't changed we just need to update the comment 
    // but if it changed we need to update reputation, votes, stats
    if (prev_vote != vote) {
      // update reviews stats
      if (vote) { 
        validator.upvotes = validator.upvotes + 1;
        validator.downvotes = validator.downvotes - 1
      } else {
        validator.downvotes = validator.downvotes - 1;
        validator.upvotes = validator.upvotes + 1;
      };
      let prev_validator_reputation = validator.reputation;
      // since we cancel the previous review and add the new one, the reputation is doubled
      reputation = reputation * 2;
      reviews.total_reputation = calculate_new_reputation(vote, reputation, reviews.total_reputation);
      validator.reputation = calculate_new_reputation(vote, reputation, prev_validator_reputation);
      // update top validators & validator reputation
      update_validators(reviews, prev_validator_reputation, validator_address);
    };

    emit(Reviewed { author: tx_context::sender(ctx), validator: validator_address, vote, reputation, comment });
  }
  
  // @dev 
  /*
  * @param 
  * @return 
  */
  
  // public fun remove(ctx: &mut TxContext) {}

  // ** Top

  // ** (Admin only) Set Parameters 

  // @dev allows the admin to set the number of epochs the user have to wait to be able to review again with the nft
  /*
  * @param admin cap 
  * @param reviews: global storage
  * @param number: the new epoch number to wait
  */
  public fun set_cooldown_epochs(_: &AdminCap, reviews: &mut Reviews, number: u64) {
    reviews.cooldown_epochs = number;
  }

  // @dev allows the admin to set the maximum number of whitelisted validators 
  /*
  * @param admin cap 
  * @param reviews: global storage
  * @param number: the new maximum (list length)
  */
  public fun set_max_top_len(_: &AdminCap, reviews: &mut Reviews, number: u64) {
    // if same number or higher do nothing since it's gonna be filled by users
    // if lower, we need to remove the lowest rated validators
    let top_length = vector::length(&reviews.top_validators);

    if (number < top_length) {
      // remove number of times the lowest validator
      let to_remove = top_length - number;

      let i = 0;
      while (i < to_remove) {
        let min_index = 0;
        let min_validator = vector::borrow(&reviews.top_validators, 0);

        let j = 1;
        
        while (j < vector::length(&reviews.top_validators)) {
          // find the lowest in up to date list
          let top_v = vector::borrow(&reviews.top_validators, j);
          
          if (top_v.reputation < min_validator.reputation) {
            min_index = j;
            min_validator = top_v;
          };

          j = j + 1;
        };

        i = i + 1;
        vector::remove(&mut reviews.top_validators, min_index);
      };
    }
  }

  // ** CORE OPERATIONS

  // @dev create a review struct 
  /*
  * @param vote: upvote or downvote
  * @param comment: a string of maximum 140 characters
  * @return the review
  */
  fun create_review(vote: bool, comment: String): Review {
    assert!(string::length(&comment) <= 140, ECommentTooLong);
    // return review
    Review { vote, comment }
  }

  // @dev This updates the top validators vector and the validator related data in both top list and reviews
  /*
  * @param reviews: global storage for reviews
  * @param nft: the nft the user pass to review
  * @param vote: up/down vote
  * @param validator_address: the validator we want to update (the one getting reviewed)
  */
  fun update_validators(reviews: &mut Reviews, prev_reputation: u64, validator_address: address) {
    // calculate new reputation for validator
    let validator = table::borrow_mut(&mut reviews.validators, validator_address);
    let new_reputation = validator.reputation;

    // modify top
    let top = reviews.top_validators;
    let top_len = vector::length(&reviews.top_validators);
    let threshold = reviews.top_threshold;
    let new_validator = TopValidator { validator_address, reputation: new_reputation };

    // we do nothing from here if it doesn't enter the top
    let (contains, index) = vector::index_of(&top, &TopValidator {validator_address, reputation: prev_reputation});
    // if it's already in the top, we update the data
    if (contains) {
      // update validator data in the top
      let top_v = vector::borrow_mut(&mut top, index);
      top_v.reputation = new_reputation;
      // if the new is lower than threshold we update the threshold
      if (new_reputation < threshold.reputation) {
        reviews.top_threshold = new_validator;
      };
    } else if (top_len < reviews.max_top_len) {
      // if the list isn't full we add it
      vector::push_back(&mut reviews.top_validators, new_validator);
    } else if (new_reputation > threshold.reputation) {
      // if the new is higher than threshold we remove the lowest validator and add new
      vector::push_back(&mut reviews.top_validators, new_validator);
      // we also have to find the new threshold
      let new_threshold = vector::borrow(&top, 0);
      let to_remove: u64 = 0;
      let i = 1;
      while (i < top_len) {
        let top_v = vector::borrow(&top, i);
        if (top_v == &threshold) { to_remove = i };
        if (top_v.reputation < new_threshold.reputation) { new_threshold = top_v; };
        i = i + 1;
      };
      vector::remove(&mut top, to_remove);
    };
  }

  // @dev calculate the new reputation given the previous one and the current review
  /*
  * @param vote: up/downvote
  * @param reputation: sqrt of principal
  * @param prev: previous reputation
  * @return new reputation
  */
  fun calculate_new_reputation(vote: bool, reputation: u64, prev: u64): u64 {
    if (vote) { prev + reputation } else if (prev < reputation) { 0 } else { prev - reputation }
  }

  // @dev calculate the reputation a user can give with a specific nft
  /*
  * @param nft: SuiYield nft the user send to review
  * @return the reputation
  */
  fun get_reputation(nft: &SuiYield): u64 {
    let (principal, _) = sui_yield::read(nft);
    math::sqrt(principal)
  }
}