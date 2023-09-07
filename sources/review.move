/// This module provide an incentive mechanism to encourage users to improve decentralization
/// by getting informed on validators and rating them
/// The validator which gets the most points during a period will be whitelisted removing fees for stakers
/// Users will be able to redeem points for rewards

module interest_lsd::review {
  use std::vector;
  use std::string::{Self, String};

  use sui::transfer;
  use sui::event::{emit};
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::tx_context::{Self, TxContext};
  use sui::table::{Self, Table};

  use interest_lsd::isui_yn::{Self, ISuiYield};
  use interest_lsd::isui::ISUI;
  use interest_lsd::admin::AdminCap;

  const ECannotReviewWithNft: u64 = 0;
  const EWrongStarNumber: u64 = 1;
  const ECommentTooLong: u64 = 2;

  struct Review has store, drop {
    stars: u64, // 100, 200, 300, 400, 500 -> [0,5] with 2 decimals 
    comment: String, // max 140 characters
  }

  struct Validator has store {
    average_stars: u64,
    review_numbers: u64,
    reviews: Table<address, Review>, // user address
  }

  struct TopValidator has store, copy, drop {
    validator_address: address,
    average_stars: u64,
  }

  // ** Shared

  struct Reviews has key {
    id: UID,
    total_stars: u64,
    total_reviews: u64,
    total_points: u64,
    cooldown_epochs: u64, // the number of epoch for which the nft cannot be used to review
    epoch_review_for_nft: Table<ID, u64>, // the epoch at which the nft was used to review
    validators_reviews: Table<address, Validator>, // validator address
    top_number: u64, // how many validators will be whitelisted
    top_threshold: TopValidator, // the lowest validator's rating in the top 
    top_validators: vector<TopValidator>,
    rewards: Coin<ISUI> // transferred from & to pool dao_coin
  }

  // ** Events

  struct Reviewed has copy, drop {
    author: address,
    validator: address,
    stars: u64,
    comment: String,
  }


  fun init(ctx: &mut TxContext) {
    transfer::share_object(Reviews {
      id: object::new(ctx),
      total_stars: 0,
      total_reviews: 0,
      total_points: 0,
      cooldown_epochs: 0,
      epoch_review_for_nft: table::new(ctx),
      validators_reviews: table::new(ctx),
      top_number: 0,
      top_threshold: TopValidator {validator_address: @0x0, average_stars: 0},
      top_validators: vector::empty(),
      rewards: coin::zero<ISUI>(ctx),
    })
  }

  // ** Reviews

  // @dev create a review and emit it
  // takes a YN nft to gate review access and limit their creation 
  /*
  * @param reviews: global storage 
  * @param nft: YN nft to verify cooldown
  * @param stars: score that user want to give
  * @param comment: maximum 140 characters explaining the choice
  * @param validator_address: the validator to review
  
  */
  public fun create(
    reviews: &mut Reviews, 
    nft: &mut ISuiYield, 
    stars: u64,
    comment: String,
    validator_address: address,
    ctx: &mut TxContext
  ) {
    // verify that nft isn't being cooled down
    let current_epoch = tx_context::epoch(ctx);
    let nft_id = object::uid_to_inner(isui_yn::uid(nft));
    let last_epoch = table::borrow(&reviews.epoch_review_for_nft, nft_id);

    assert!(current_epoch > *last_epoch + reviews.cooldown_epochs, ECannotReviewWithNft);
    
    let review = create_review(stars, comment);
    update_validators(reviews, review.stars, validator_address);

    let new_epoch = table::borrow_mut(&mut reviews.epoch_review_for_nft, nft_id);
    *new_epoch = current_epoch;
    table::add(
      &mut table::borrow_mut(&mut reviews.validators_reviews, validator_address).reviews, 
      tx_context::sender(ctx), 
      review
    );

    emit(Reviewed { author: tx_context::sender(ctx), validator: validator_address, stars, comment });
  }

  // @dev update a review and emit it
  // takes a YN nft to gate review access and limit their creation 
  /*
  * @param reviews: global storage 
  * @param nft: YN nft to verify cooldown
  * @param stars: score that user want to give
  * @param comment: maximum 140 characters explaining the choice
  * @param validator_address: the validator to review
  
  */
  public fun update(
    reviews: &mut Reviews, 
    nft: &mut ISuiYield, 
    stars: u64,
    comment: String,
    validator_address: address,
    ctx: &mut TxContext
  ) {
    // verify that nft isn't being cooled down
    let current_epoch = tx_context::epoch(ctx);
    let nft_id = object::uid_to_inner(isui_yn::uid(nft));
    let last_epoch = table::borrow(&reviews.epoch_review_for_nft, nft_id);

    assert!(current_epoch > *last_epoch + reviews.cooldown_epochs, ECannotReviewWithNft);
    
    let review = create_review(stars, comment);
    update_validators(reviews, review.stars, validator_address);

    let new_epoch = table::borrow_mut(&mut reviews.epoch_review_for_nft, nft_id);
    *new_epoch = current_epoch;

    let prev_review = table::borrow_mut(
      &mut table::borrow_mut(&mut reviews.validators_reviews, validator_address).reviews, 
      tx_context::sender(ctx)
    );
    *prev_review = review;

    emit(Reviewed { author: tx_context::sender(ctx), validator: validator_address, stars, comment });
  }
  
  // @dev 
  /*
  * @param 
  * @return 
  */
  
  // public fun remove(ctx: &mut TxContext) {}

  // ** Top

  // ** Rewards

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
  public fun set_top_number(_: &AdminCap, reviews: &mut Reviews, number: u64) {
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
          
          if (top_v.average_stars < min_validator.average_stars) {
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
  * @param stars: a number between 0 and 5
  * @param comment: a string of maximum 140 characters
  * @return the review
  */
  fun create_review(stars: u64, comment: String): Review {
    // verify stars = [0,5] and comment length <= 140
    assert!(stars <= 5, EWrongStarNumber);
    assert!(string::length(&comment) <= 140, ECommentTooLong);

    // return review
    Review { stars: stars * 100, comment }
  }

  // @dev This updates the top validators vector and the validator related data in both top list and reviews
  /*
  * @param reviews: global storage for reviews
  * @param review: a review struct that should be created before
  * @param validator_address: the validator we want to update (the one getting reviewed)
  */
  fun update_validators(reviews: &mut Reviews, stars: u64, validator_address: address) {
    // calculate average stars for validator
    let validator = table::borrow_mut(&mut reviews.validators_reviews, validator_address);
    let average_stars = 
      ((validator.average_stars * validator.review_numbers) + stars) 
      / (validator.review_numbers + 1);

    // modify top
    let top = reviews.top_validators;
    let prev_key = TopValidator {validator_address, average_stars: validator.average_stars};
    let top_len = vector::length(&reviews.top_validators);
    let threshold = reviews.top_threshold;

    if (vector::contains(&top, &prev_key)) {
      // if it's already in the top, we update the data
      let (_, index) = vector::index_of(&top, &prev_key);
      let top_v = vector::borrow_mut(&mut top, index);
      top_v.average_stars = average_stars;
    } else if (top_len < reviews.top_number) {
      // if the list isn't full we add it
      vector::push_back(&mut reviews.top_validators, TopValidator { validator_address, average_stars });
    } else if (average_stars > threshold.average_stars) {
      // if the new is higher than threshold we remove the lowest validator and add new
      // we also have to find the new threshold
      let i = 0;
      let to_remove: u64 = 0;
      let new_threshold = TopValidator { validator_address: @0x0, average_stars: 500 };
      while (i < top_len) {
        let top_v = vector::borrow(&top, i);
        if (top_v == &threshold) { to_remove = i };
        if (top_v.average_stars < new_threshold.average_stars) { new_threshold = *top_v; };
        i = i + 1;
      };
      vector::remove(&mut top, to_remove);
    };

    // update data
    validator.average_stars = average_stars;
    validator.review_numbers = validator.review_numbers + 1;
  }
}