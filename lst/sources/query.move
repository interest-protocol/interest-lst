module interest_lst::query {
  use std::option;
  use std::vector;

  use sui::linked_table;

  use sui_system::staking_pool;
 
  use interest_lst::fee_utils::calculate_fee_percentage;
  use interest_lst::interest_lst::{Self, InterestLST};


  struct StakePosition has store, drop {
    epoch: u64,
    amount: u64
  }

  struct ValidatorStakePosition has store, drop {
    validator: address,
    total_principal: u64,
    stakes: vector<StakePosition>
  }
  
  public fun get_validator_fee(self: &mut InterestLST, validator_address: address): u128 {
    if (interest_lst::is_whitelisted(self, validator_address)) return 0;
    
    let (_, _, _, total_principal, fee, _, _) = interest_lst::read_state(self);
    let fee = *fee;
    let (_, validator_principal) = interest_lst::read_validator_data(self, validator_address);

    calculate_fee_percentage(&fee, (validator_principal as u128), (total_principal as u128))
  }

  public fun get_validators_fee_vector(self: &mut InterestLST, validators: vector<address>): vector<u128> {
    let len = vector::length(&validators);
    let i = 0;
    let result = vector::empty();

    while(len > i) {
      vector::push_back(&mut result, get_validator_fee(self, *vector::borrow(&validators, i)));
      i = i + 1;
    };
    
    result
  }

  public fun get_validators_stake_position(self: &mut InterestLST, from: address, to: address): vector<ValidatorStakePosition> {
    let data = vector::empty<ValidatorStakePosition>();

    push_stake_position(self, &mut data, from);

    let (_, _, validators_table, _, _, _, _) = interest_lst::read_state(self);

    let next_validator = linked_table::next(validators_table, from);
    
    while (option::is_some(next_validator)) {
      let validator_address = *option::borrow(next_validator);

      push_stake_position(self, &mut data, validator_address);

      if (validator_address == to) break;

      let (_, _, validators_table, _, _, _, _) = interest_lst::read_state(self);

      next_validator = linked_table::next(validators_table, validator_address);
    };

    data
  }

  fun push_stake_position(self: &mut InterestLST, data: &mut vector<ValidatorStakePosition>, validator_address: address) {
    let (staked_sui_table, total_principal) = interest_lst::read_validator_data(self, validator_address);

    let validator_stake = ValidatorStakePosition { validator: validator_address, total_principal, stakes: vector::empty() };

    if (total_principal != 0) {

      let next_key = linked_table::front(staked_sui_table);

      while (option::is_some(next_key)) {
        let activation_epoch = *option::borrow(next_key);
          
        let staked_sui = linked_table::borrow(staked_sui_table, activation_epoch);
          
        vector::push_back(&mut validator_stake.stakes, 
        StakePosition { epoch: staking_pool::stake_activation_epoch(staked_sui), amount: staking_pool::staked_sui_amount(staked_sui) });

        next_key = linked_table::next(staked_sui_table, activation_epoch);
        };
    };

    vector::push_back(data, validator_stake);
  }
}