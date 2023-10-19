module interest_lst::query {
  // use std::option;
  // use std::vector;

  // use sui::linked_table::{Self, LinkedTable};

  // use sui_system::staking_pool;
  
  // use interest_lst::fee_utils::calculate_fee_percentage;
  // use interest_lst::pool::{Self, PoolStorage, ValidatorData};

  // struct StakePosition has store, drop {
  //   epoch: u64,
  //   amount: u64
  // }

  // struct ValidatorStakePosition has store, drop {
  //   validator: address,
  //   total_principal: u64,
  //   stakes: vector<StakePosition>
  // }
  
  // // @dev It allows the frontend to find the current fee of a specific validator
  // /*
  // * @param pool_storage The shared object of the interest_lst::pool module
  // * @param validator_address The address of a validator
  // * @return The fee in 1e18
  // */
  // public fun get_validator_fee(storage: &PoolStorage, validator_address: address): u128 {
  //   if (pool::is_whitelisted(storage, validator_address)) return 0;
    
  //   let (_, _, validator_table, total_principal, fee, _, _) = pool::read_pool_storage(storage);
  //   let (_, validator_principal) = pool::read_validator_data(linked_table::borrow(validator_table, validator_address));

  //   calculate_fee_percentage(fee, (validator_principal as u128), (total_principal as u128))
  // }

  // // @dev It allows the frontend to find the current fee for all validators
  // /*
  // * @param pool_storage The shared object of the interest_lst::pool module
  // * @param validators A vector with the address of all validators
  // * @return The fee in 1e18
  // */
  // public fun get_validators_fee_vector(storage: &PoolStorage, validators: vector<address>): vector<u128> {
  //   let len = vector::length(&validators);
  //   let i = 0;
  //   let result = vector::empty();

  //   while(len > i) {
  //     vector::push_back(&mut result, get_validator_fee(storage, *vector::borrow(&validators, i)));
  //     i = i + 1;
  //   };
    
  //   result
  // }

  // // @dev It allows the frontend to know how much Sui was staked in each validator in our LST
  // // Because the validator list can be infinite and vectors are ideal for < 1000 items. We allow the caller to get a specific range
  // /*
  // * @param pool_storage The shared object of the interest_lst::pool module
  // * @param from The first key to get
  // * @param to The last key to get
  // * @return vector<ValidatorStakePosition>
  // */
  // public fun get_validators_stake_position(storage: &PoolStorage, from: address, to: address): vector<ValidatorStakePosition> {
  //   let data = vector::empty<ValidatorStakePosition>();

  //   let (_, _, validators_table, _, _, _, _) = pool::read_pool_storage(storage);

  //   push_stake_position(&mut data, validators_table, from);

  //   let next_validator = linked_table::next(validators_table, from);
    
  //   while (option::is_some(next_validator)) {
  //     let validator_address = *option::borrow(next_validator);

  //     push_stake_position(&mut data, validators_table, validator_address);

  //     if (validator_address == to) break;

  //     next_validator = linked_table::next(validators_table, validator_address);
  //   };

  //   data
  // }

  // fun push_stake_position(data: &mut vector<ValidatorStakePosition>, validators_table: &LinkedTable<address, ValidatorData>, validator_address: address) {
  //   let validator_data = linked_table::borrow(validators_table, validator_address);

  //   let (staked_sui_table, total_principal) = pool::read_validator_data(validator_data);

  //   let validator_stake = ValidatorStakePosition { validator: validator_address, total_principal, stakes: vector::empty() };

  //   if (total_principal != 0) {

  //     let next_key = linked_table::front(staked_sui_table);

  //     while (option::is_some(next_key)) {
  //       let activation_epoch = *option::borrow(next_key);
          
  //       let staked_sui = linked_table::borrow(staked_sui_table, activation_epoch);
          
  //       vector::push_back(&mut validator_stake.stakes, 
  //       StakePosition { epoch: staking_pool::stake_activation_epoch(staked_sui), amount: staking_pool::staked_sui_amount(staked_sui) });

  //       next_key = linked_table::next(staked_sui_table, activation_epoch);
  //       };
  //   };

  //   vector::push_back(data, validator_stake);
  // }
}