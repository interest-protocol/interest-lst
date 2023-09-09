/// This module provide an incentive mechanism to encourage users to improve decentralization
/// by getting informed on validators and rating them
/// The validator which gets the most points during a period will be whitelisted removing fees for stakers

module interest_lsd::review {
  // use std::vector;
  // use std::string::{Self, String};

  // use sui::transfer;
  // use sui::event::{emit};
  // use sui::object::{Self, UID, ID};
  // use sui::tx_context::{Self, TxContext};
  // use sui::table::{Self, Table};
  // use sui::math;

  // use interest_lsd::sui_yield::{Self, SuiYield};
  // use interest_lsd::admin::AdminCap;

  // const ECannotReviewWithNft: u64 = 0;
  // const EWrongStarNumber: u64 = 1;
  // const ECommentTooLong: u64 = 2;

  // struct Review has store, drop {
  //   vote: bool,
  //   comment: String, // max 140 
  // }

  // struct Validator has store {
  //   upvotes: u64,
  //   downvotes: u64,
  //   reputation: u64, // + upvotes * stakes - downvotes * stakes
  //   reviews: Table<address, Review>, // user address
  // }

  // struct TopValidator has store, copy, drop {
  //   validator_address: address,
  //   reputation: u64,
  // }

  // // ** Shared

  // struct Reviews has key {
  //   id: UID,
  //   total_reviews: u64,
  //   total_reputation: u64, // + upvotes * stakes - downvotes * stakes
  //   cooldown_epochs: u64, // the number of epoch for which the nft cannot be used to review
  //   epoch_review_for_nft: Table<ID, u64>, // the epoch at which the nft was used to review
  //   validators_reviews: Table<address, Validator>, // validator address
  //   top_number: u64, // how many validators will be whitelisted
  //   top_threshold: TopValidator, // the lowest validator's rating in the top 
  //   top_validators: vector<TopValidator>, // the validators that will be whitelisted
  // }

  // // ** Events

  // struct Reviewed has copy, drop {
  //   author: address,
  //   validator: address,
  //   vote: bool,
  //   reputation: u64,
  //   comment: String,
  // }


  // fun init(ctx: &mut TxContext) {
  //   transfer::share_object(Reviews {
  //     id: object::new(ctx),
  //     total_reviews: 0,
  //     total_reputation: 0,
  //     cooldown_epochs: 0,
  //     epoch_review_for_nft: table::new(ctx),
  //     validators_reviews: table::new(ctx),
  //     top_number: 0,
  //     top_threshold: TopValidator {validator_address: @0x0, reputation: 0},
  //     top_validators: vector::empty(),
  //   })
  // }

  // // ** Reviews

  // // @dev create a review and emit it
  // // takes a YN nft to gate review access and limit their creation 
  // /*
  // * @param reviews: global storage 
  // * @param nft: Sui Yield nft to verify cooldown
  // * @param validator_address: the validator to review
  // * @param vote: up/down vote
  // * @param comment: maximum 140 characters explaining the choice
  
  // */
  // public fun create(
  //   reviews: &mut Reviews, 
  //   nft: &mut SuiYield, 
  //   validator_address: address,
  //   vote: bool,
  //   comment: String,
  //   ctx: &mut TxContext
  // ) {
  //   // verify that nft isn't being cooled down
  //   let current_epoch = tx_context::epoch(ctx);
  //   let nft_id = object::uid_to_inner(sui_yield::uid(nft));
  //   let last_epoch = table::borrow(&reviews.epoch_review_for_nft, nft_id);

  //   assert!(current_epoch > *last_epoch + reviews.cooldown_epochs, ECannotReviewWithNft);

  //   let (principal, _) = sui_yield::read(nft);
  //   let reputation = math::sqrt(principal);
    
  //   let review = create_review(vote, comment);
  //   update_validators(reviews, nft, vote, validator_address);

  //   let prev_epoch = table::borrow_mut(&mut reviews.epoch_review_for_nft, nft_id);
  //   *prev_epoch = current_epoch;

  //   let validator = table::borrow_mut(&mut reviews.validators_reviews, validator_address);
  //   table::add(
  //     &mut validator.reviews, 
  //     tx_context::sender(ctx), 
  //     review
  //   );

  //   if (vote) { validator.upvotes = validator.upvotes + 1 } else { validator.downvotes = validator.downvotes - 1 };
  //   reviews.total_reviews = reviews.total_reviews + 1;
  //   reviews.total_reputation = calculate_reputation(nft, reviews.total_reputation, vote);

  //   emit(Reviewed { author: tx_context::sender(ctx), validator: validator_address, vote, reputation, comment });
  // }

  // // @dev update a review and emit it
  // // takes a YN nft to gate review access and limit their creation 
  // /*
  // * @param reviews: global storage 
  // * @param nft: Sui Yield nft to verify cooldown
  // * @param validator_address: the validator to review
  // * @param vote: up/down vote
  // * @param comment: maximum 140 characters explaining the choice
  
  // */
  // public fun update(
  //   reviews: &mut Reviews, 
  //   nft: &mut SuiYield, 
  //   validator_address: address,
  //   vote: bool,
  //   comment: String,
  //   ctx: &mut TxContext
  // ) {
  //   // verify that nft isn't being cooled down
  //   let current_epoch = tx_context::epoch(ctx);
  //   let nft_id = object::uid_to_inner(sui_yield::uid(nft));
  //   let last_epoch = table::borrow(&reviews.epoch_review_for_nft, nft_id);

  //   assert!(current_epoch > *last_epoch + reviews.cooldown_epochs, ECannotReviewWithNft);

  //   let (principal, _) = sui_yield::read(nft);
  //   let reputation = math::sqrt(principal);
    
  //   let review = create_review(vote, comment);
  //   update_validators(reviews, nft, vote, validator_address);

  //   let prev_epoch = table::borrow_mut(&mut reviews.epoch_review_for_nft, nft_id);
  //   *prev_epoch = current_epoch;

  //   let validator = table::borrow_mut(&mut reviews.validators_reviews, validator_address);
  //   let prev_review = table::borrow_mut(
  //     &mut validator.reviews, 
  //     tx_context::sender(ctx)
  //   );

  //   if (vote) { validator.upvotes = validator.upvotes + 1 } else { validator.downvotes = validator.downvotes - 1 };
  //   if (prev_review.vote) { validator.upvotes = validator.upvotes - 1 } else { validator.downvotes = validator.downvotes + 1 };
  //   reviews.total_reviews = reviews.total_reviews + 1;
  //   reviews.total_reputation = calculate_reputation(nft, reviews.total_reputation, vote);

  //   *prev_review = review;

  //   emit(Reviewed { author: tx_context::sender(ctx), validator: validator_address, vote, reputation, comment });
  // }
  
  // // @dev 
  // /*
  // * @param 
  // * @return 
  // */
  
  // // public fun remove(ctx: &mut TxContext) {}

  // // ** Top

  // // ** (Admin only) Set Parameters 

  // // @dev allows the admin to set the number of epochs the user have to wait to be able to review again with the nft
  // /*
  // * @param admin cap 
  // * @param reviews: global storage
  // * @param number: the new epoch number to wait
  // */
  // public fun set_cooldown_epochs(_: &AdminCap, reviews: &mut Reviews, number: u64) {
  //   reviews.cooldown_epochs = number;
  // }

  // // @dev allows the admin to set the maximum number of whitelisted validators 
  // /*
  // * @param admin cap 
  // * @param reviews: global storage
  // * @param number: the new maximum (list length)
  // */
  // public fun set_top_number(_: &AdminCap, reviews: &mut Reviews, number: u64) {
  //   // if same number or higher do nothing since it's gonna be filled by users
  //   // if lower, we need to remove the lowest rated validators
  //   let top_length = vector::length(&reviews.top_validators);

  //   if (number < top_length) {
  //     // remove number of times the lowest validator
  //     let to_remove = top_length - number;

  //     let i = 0;
  //     while (i < to_remove) {
  //       let min_index = 0;
  //       let min_validator = vector::borrow(&reviews.top_validators, 0);

  //       let j = 1;
        
  //       while (j < vector::length(&reviews.top_validators)) {
  //         // find the lowest in up to date list
  //         let top_v = vector::borrow(&reviews.top_validators, j);
          
  //         if (top_v.reputation < min_validator.reputation) {
  //           min_index = j;
  //           min_validator = top_v;
  //         };

  //         j = j + 1;
  //       };

  //       i = i + 1;
  //       vector::remove(&mut reviews.top_validators, min_index);
  //     };
  //   }
  // }

  // // ** CORE OPERATIONS

  // // @dev create a review struct 
  // /*
  // * @param vote: upvote or downvote
  // * @param comment: a string of maximum 140 characters
  // * @return the review
  // */
  // fun create_review(vote: bool, comment: String): Review {
  //   assert!(string::length(&comment) <= 140, ECommentTooLong);
  //   // return review
  //   Review { vote, comment }
  // }

  // // @dev This updates the top validators vector and the validator related data in both top list and reviews
  // /*
  // * @param reviews: global storage for reviews
  // * @param nft: the nft the user pass to review
  // * @param vote: up/down vote
  // * @param validator_address: the validator we want to update (the one getting reviewed)
  // */
  // fun update_validators(reviews: &mut Reviews, nft: &SuiYield, vote: bool, validator_address: address) {
  //   // calculate new reputation for validator
  //   let validator = table::borrow_mut(&mut reviews.validators_reviews, validator_address);
  //   let new_reputation = calculate_reputation(nft, validator.reputation, vote);

  //   // modify top
  //   let top = reviews.top_validators;
  //   let prev_key = TopValidator {validator_address, reputation: validator.reputation};
  //   let top_len = vector::length(&reviews.top_validators);
  //   let threshold = reviews.top_threshold;

  //   // if it's already in the top, we update the data
  //   let (contains, index) = vector::index_of(&top, &prev_key);
  //   if (contains) {
  //     // if the new is lower than threshold we update the threshold
  //     if (new_reputation < threshold.reputation) {
  //       reviews.top_threshold = TopValidator { validator_address, reputation: new_reputation };
  //     } else {
  //       let top_v = vector::borrow_mut(&mut top, index);
  //       top_v.reputation = new_reputation;
  //     }
  //   } else if (top_len < reviews.top_number) {
  //     // if the list isn't full we add it
  //     vector::push_back(&mut reviews.top_validators, TopValidator { validator_address, reputation: new_reputation });
  //   } else if (new_reputation > threshold.reputation) {
  //     // if the new is higher than threshold we remove the lowest validator and add new
  //     vector::push_back(&mut reviews.top_validators, TopValidator { validator_address, reputation: new_reputation });
  //     // we also have to find the new threshold
  //     let new_threshold = vector::borrow(&top, 0);
  //     let to_remove: u64 = 0;
  //     let i = 1;
  //     while (i < top_len) {
  //       let top_v = vector::borrow(&top, i);
  //       if (top_v == &threshold) { to_remove = i };
  //       if (top_v.reputation < new_threshold.reputation) { new_threshold = top_v; };
  //       i = i + 1;
  //     };
  //     vector::remove(&mut top, to_remove);
  //   };

  //   // update data
  //   validator.reputation = new_reputation;
  // }

  // fun calculate_reputation(nft: &SuiYield, prev: u64, vote: bool): u64 {
  //   let (principal, _) = sui_yield::read(nft);
  //   if (vote) { prev + math::sqrt(principal) } else { prev - math::sqrt(principal) }
  // }
}