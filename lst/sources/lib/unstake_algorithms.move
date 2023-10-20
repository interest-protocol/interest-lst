module interest_lst::unstake_algorithms {
  use std::vector;
  use std::option;

  use sui::linked_table;
  use sui::tx_context::{Self, TxContext};

  use sui_system::staking_pool;

  use interest_lst::constants;
  use interest_lst::interest_lst::{Self, InterestLST};
  use interest_lst::unstake_utils::{
    UnstakePayload, 
    make_unstake_payload, 
    make_epoch_amount, 
    update_unstake_payload_amounts
  };


    // TODO ADD other algorithms (Example unstake from lowest APY etc)

  public fun default_unstake_algorithm(state: &mut InterestLST, amount: u64, ctx: &mut TxContext): vector<UnstakePayload> {
    let total_value_unstaked = 0;
    let data = vector::empty();

    // Get the first validator in the linked_table
    let (_, _, validators_table, _, _, _, _) = interest_lst::read_state(state);

    let next_validator = linked_table::front(validators_table);

    let min_stake_amount = constants::min_stake_amount();

    // While there is a next validator, we keep looping
    while(option::is_some(next_validator)) {
      // Save the validator address in memory
      let validator_address = *option::borrow(next_validator);
      

      // Borrow Mut the validator data
      let (staked_sui_table, total_principal) = interest_lst::read_validator_data(state, validator_address);

      let unstake_payload = make_unstake_payload(validator_address, vector::empty());

      // If the validator has no staked Sui, we move unto the next one
      if (total_principal != 0) {

        let next_key = linked_table::front(staked_sui_table);

        while(option::is_some(next_key)) {
          // Save the first key (epoch) on the staked sui table in memory
          let activation_epoch = *option::borrow(next_key);

          // We are only allowed to unstake if the Staked Suis are active
          if (tx_context::epoch(ctx) >= activation_epoch) {
            // Remove the Staked Sui - to make the table shorter for future iterations
            let staked_sui = linked_table::borrow(staked_sui_table, activation_epoch);

            // Save the principal in Memory
            let value = staking_pool::staked_sui_amount(staked_sui);

            // Find out how much amount we have left to unstake
            let amount_left = amount - total_value_unstaked;

            if (value >= amount_left + min_stake_amount) {
              total_value_unstaked = total_value_unstaked  + amount_left;
              vector::push_back(update_unstake_payload_amounts(&mut unstake_payload), make_epoch_amount(activation_epoch, amount_left, true) );
            } else {
              // If we cannot split, we simply unstake the whole Staked Sui
              total_value_unstaked = total_value_unstaked  + value;
              vector::push_back(update_unstake_payload_amounts(&mut unstake_payload), make_epoch_amount(activation_epoch, value, false ) );
            };
          };

          

          // Insanity check to make sure we d not keep looping for no reason
          if (total_value_unstaked >= amount) break;
          // Move in the next epoch
          next_key = linked_table::next(staked_sui_table, activation_epoch);
        };
      };

      vector::push_back(&mut data, unstake_payload);

      // No point to keep going if we have unstaked enough      
      if (total_value_unstaked >= amount) break;
      let (_, _, validators_table, _, _, _, _) = interest_lst::read_state(state);
      // Get the next validator to keep looping
      next_validator = linked_table::next(validators_table, validator_address);
    };   

    data 
  }
}