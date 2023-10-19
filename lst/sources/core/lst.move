// @Authors - JMVC <> Thouny
// This contract manages the minting/burning of iSui, iSUIP, and iSUIY
// iSui is a share of the total SUI principal + rewards this module owns
// iSUIP is always 1 SUI as it represents the principal owned by this module
// iSUIY represents the yield component of a iSUIP
module interest_lst::interest_lst { 
  use sui::sui::SUI;
  use sui::dynamic_field as df;
  use sui::object::{Self, UID};
  use sui::tx_context::TxContext;
  use sui::transfer::share_object;
  use sui::coin::{Coin, TreasuryCap};

  use sui_system::sui_system::SuiSystemState;

  use suitears::semi_fungible_token::{SemiFungibleToken, SftTreasuryCap};

  use yield::yield::{Self, Yield, YieldCap};

  use interest_lst::isui::ISUI;
  use interest_lst::isui_yield::ISUI_YIELD;
  use interest_lst::isui_principal::ISUI_PRINCIPAL;
  use interest_lst::interest_lst_inner_state::{Self as inner_state, State};

  // ** Structs

  struct StateKey has store, drop, copy {}

  struct InterestLST has key {
    id: UID
  }

  fun init(ctx: &mut TxContext) {
    share_object(InterestLST { id: object::new(ctx) });
  }

  // @dev this function cannot be called again because the caps cannot be created again
  public fun create_genesis_state(
    self: &mut InterestLST,
    isui_cap: TreasuryCap<ISUI>,
    principal_cap: SftTreasuryCap<ISUI_PRINCIPAL>,
    yield_cap: YieldCap<ISUI_YIELD>,
    ctx: &mut TxContext
  ) {
    let genesis_state = inner_state::create_genesis_state(isui_cap, principal_cap, yield_cap, ctx);
    df::add(&mut self.id, StateKey {}, genesis_state);
  }

  public fun update_fund(
    sui_state: &mut SuiSystemState,
    self: &mut InterestLST,
    ctx: &mut TxContext,
  ) {
    let state = load_state_mut(self);
    inner_state::update_fund(sui_state, state, ctx);
  }


  fun load_state(self: &mut InterestLST): &State {
    df::borrow_mut(&mut self.id, StateKey {})
  }

  fun load_state_mut(self: &mut InterestLST): &mut State {
    df::borrow_mut(&mut self.id, StateKey {})
  }

//   // ** Events

//   struct MintISui has copy, drop {
//     sender: address,
//     sui_amount: u64,
//     isui_amount: u64,
//     validator: address
//   }

//   struct BurnISui has copy, drop {
//     sender: address,
//     sui_amount: u64,
//     isui_amount: u64,
//   }

//   struct MintStrippedBond has copy, drop {
//     sender: address,
//     sui_amount: u64,
//     sui_yield_id: ID,
//     sui_principal_id: ID,
//     validator: address
//   }

//   struct CallBond has copy, drop {
//     sender: address,
//     sui_amount: u64,
//     maturity: u64    
//   }

//   struct BurnSuiPrincipal has copy, drop {
//     sender: address,
//     sui_amount: u64
//   }

//   struct ClaimYield has copy, drop {
//     sender: address,
//     sui_yield_id: ID,
//     sui_amount: u64,   
//   }

//   // Emitted when the DAO updates the fee
//   struct NewFee has copy, drop {
//     base: u128,
//     kink: u128,
//     jump: u128
//   }

//   // Emitted when the DAO withdraws some rewards
//   // Most likely to cover the {updatePools} calls
//   struct DaoWithdraw has copy, drop {
//     sender: address,
//     amount: u64
//   }

//   struct UpdatePool has copy, drop {
//     rewards: u64,
//     principal: u64
//   }

//   struct StartUpgrade has copy, drop {
//     version: u64
//   }

//   struct CancelUpgrade has copy, drop {}

//   struct FinishUpgrade has copy, drop {
//     version: u64
//   }


//   fun init(otw: POOL, ctx: &mut TxContext) {
//     // Share the PoolStorage Object with the Sui network
//     transfer::share_object(
//         PoolStorage {
//         id: object::new(ctx),
//         pool: rebase::new(),
//         last_epoch: 0,
//         validators_table: linked_table::new(ctx),
//         total_principal: 0,
//         fee: new_fee(),
//         whitelist_validators: vector::empty(),
//         pool_history: linked_table::new(ctx),
//         dust: balance::zero(),
//         dao_balance: balance::zero(),
//         rate: 0,
//         publisher: package::claim(otw, ctx),
//         total_activate_staked_sui: 0,
//         version: version::current_version() // Start the protocol at version 1. Init function is not called again on upgrades
//       }
//     );
//   }

//   // @dev It returns the exchange rate from ISUI to SUI
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param isui_amount The amount of ISUI
//   * @return the exchange rate
//   */
//   public fun get_exchange_rate_isui_to_sui(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage, 
//     isui_amount: u64,
//     ctx: &mut TxContext
//   ): u64 {
//     update_pool(wrapper, storage, ctx);
//     rebase::to_elastic(&storage.pool, isui_amount, false)
//   }

//   // @dev It returns the exchange rate from SUI to ISUI
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param sui_amount The amount of SUI
//   * @param return the exchange rate
//   */
//   public fun get_exchange_rate_sui_to_isui(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage, 
//     sui_amount: u64,
//     ctx: &mut TxContext
//   ): u64 {
//     update_pool(wrapper, storage, ctx);
//     rebase::to_base(&storage.pool, sui_amount, false)
//   }

//   // @dev It returns how much Sui a SuiYield can claim
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param sft The SuiYield
//   * @param maturity the backup maturity
//   * @return the exchange rate
//   */
//   public fun get_pending_yield(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage, 
//     sft: &SuiYield,
//     maturity: u64,
//     ctx: &mut TxContext
//   ): u64 {

//     // We update the pool to make sure the rewards are up to date
//     update_pool(wrapper, storage, ctx);

//     get_pending_yield_logic(storage, sft, maturity, ctx)
//   }

//   // @dev This function costs a lot of gas and must be called before any interaction with Interest lst because it updates the pool. The pool is needed to ensure all 3 Coins' exchange rate is accurate.
//   // Anyone can call this function
//   // It will ONLY RUN ONCE per epoch
//   // Dev Team will call as soon as a new epoch starts so the first user does not need to incur this cost
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   */
//   entry public fun update_pool(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     ctx: &mut TxContext,
//   ) {
//     // Save the current epoch in memory
//     let epoch = tx_context::epoch(ctx);

//     //If the function has been called this epoch, we do not need to do anything else
//     // If there are no shares in the pool, it means there is no sui being staked. So there are no updates
//     if (epoch == storage.last_epoch || rebase::base(&storage.pool) == 0) return;

//     let total_rewards = 0;
//     let total_activate_staked_sui = 0;

//     // Get the first validator in the linked_table
//     let next_validator = linked_table::front(&storage.validators_table);
    
//     // We iterate through all validators. This can grow to 1000+
//     while (option::is_some(next_validator)) {
//       // Save the validator address in memory. We first check that it exists above.
//       let validator_address = *option::borrow(next_validator);

//       // Get the validator data
//       let validator_data = linked_table::borrow(&storage.validators_table, validator_address);

//       let pool_exchange_rates = sui_system::pool_exchange_rates(wrapper, &validator_data.staking_pool_id);
//       // If the validator is deactivated, we need to find its most recent exchange rate
//       let current_exchange_rate = get_most_recent_exchange_rate(pool_exchange_rates, epoch);

//       // If the validator does not have any sui staked, we to the next validator
//       if (validator_data.total_principal != 0) {
//         // We calculate the total rewards we will get based on our current principal staked in the validator

//         let next_key = linked_table::front(&validator_data.staked_sui_table);

//         while (option::is_some(next_key)) {
//           let activation_epoch = *option::borrow(next_key);
          
//           let staked_sui = linked_table::borrow(&validator_data.staked_sui_table, activation_epoch);
          
//           // We only update the rewards if the {epoch} is equal or greater than the {activation_epoch}
//           // Otherwise, these sui have not accrued any rewards
//           // We update the total rewards
//           if (epoch >= activation_epoch) {
//             let amount = staking_pool::staked_sui_amount(staked_sui);
//             total_rewards = total_rewards + calc_staking_pool_rewards(
//               // ** IMPORTANT AUDITORS - is it possible for a validator to not have the activation_epoch of a StakedSui on their PoolExchangeRate ????
//               table::borrow(pool_exchange_rates, activation_epoch),
//               current_exchange_rate,
//               amount
//             );
//             total_activate_staked_sui = total_activate_staked_sui + amount;
//           };

//           next_key = linked_table::next(&validator_data.staked_sui_table, activation_epoch);
//         };
//       };
      
//       // Point the next_validator to the next one
//       next_validator = linked_table::next(&storage.validators_table, validator_address);
//     };

//     // We update the total Sui (principal + rewards) 
//     rebase::set_elastic(&mut storage.pool, total_rewards + storage.total_principal);
//     // Update the last_epoch
//     storage.last_epoch = epoch;
//     storage.total_activate_staked_sui = total_activate_staked_sui;

//     // We calculate a weighted rate to avoid manipulations (average_rate * days_elapsed) + current_rate / days_elapsed + 1
//     let num_of_epochs = (linked_table::length(&storage.pool_history) as u256);
//     let current_rate = (fdiv((total_rewards as u128),(storage.total_principal as u128)) as u64);

//     storage.rate = if (storage.rate == 0) 
//     { current_rate } 
//     else 
//     { ((((current_rate as u256) * num_of_epochs) + (storage.rate as u256)) / (num_of_epochs + 1) as u64) };

//     // We save the epoch => Pool Rebase
//     linked_table::push_back(
//       &mut storage.pool_history, 
//       epoch, 
//       storage.pool
//     );
//     emit(UpdatePool { principal: storage.total_principal, rewards: total_rewards  });
//   }

//   // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
//   * @param token The Sui Coin, the sender wishes to stake
//   * @param validator_address The Sui Coin will be staked in this validator
//   * @return Coin<ISUI> in exchange for the Sui deposited
//   */
//   public fun mint_isui(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     interest_sui_storage: &mut InterestSuiStorage,
//     token: Coin<SUI>,
//     validator_address: address,
//     ctx: &mut TxContext,
//   ): Coin<ISUI> {
//     // Ensure that users are using the correct version
//     assert_current_version(storage);
    
//     let sui_amount = coin::value(&token);
    
//     // mint_isui_logic will update the pool
//     let shares = mint_isui_logic(wrapper, storage, token, validator_address, ctx);

//     let isui_amount = if (is_whitelisted(storage, validator_address)) {
//       shares
//     } else {
//       let validator_principal = linked_table::borrow(&storage.validators_table, validator_address).total_principal;
//       charge_isui_mint(
//         storage, 
//         interest_sui_storage, 
//         validator_principal, 
//         shares, 
//         ctx
//       )
//     };

//     emit(MintISui { validator: validator_address, sender: tx_context::sender(ctx), sui_amount, isui_amount });

//     // Mint iSUI to the caller
//     isui::mint(interest_sui_storage, &storage.publisher, isui_amount, ctx)
//   }

//   // @dev This function burns ISUI and unstake Sui 
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
//   * @param token The iSui Coin, the sender wishes to burn
//   * @param validator_address The address of a validator to stake any leftover Sui
//   * @param unstake_payload contains the data to select which validators to unstake
//   * @return Coin<SUI> in exchange for the iSui burned
//   */
//   public fun burn_isui(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     interest_sui_storage: &mut InterestSuiStorage,
//     token: Coin<ISUI>,
//     validator_address: address,
//     unstake_payload: vector<UnstakePayload>,
//     ctx: &mut TxContext,
//   ): Coin<SUI> {
//     // Ensure that users are using the correct version
//     assert_current_version(storage);

//     // Need to update the entire state of Sui/Sui Rewards once every epoch
//     // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
//     update_pool(wrapper, storage, ctx);

//     let isui_amount = isui::burn(interest_sui_storage, &storage.publisher, token, ctx);

//     // Update the pool 
//     // Remove the shares
//     // Burn the iSUI
//     let sui_amount = rebase::sub_base(&mut storage.pool, isui_amount, false);

//     emit(BurnISui { sender: tx_context::sender(ctx), sui_amount, isui_amount });

//     // Unstake Sui
//     remove_staked_sui(wrapper, storage, sui_amount, unstake_payload,  validator_address, ctx)
//   }

//   // @dev This function stakes Sui in a validator chosen by the sender and mints a stripped bond (SuiPrincipal + Sui Yield). 
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param interest_sui_storage The shared object of ISUI, it contains the treasury_cap. We need it to mint ISUI
//   * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to mint.
//   * @param sui_yield_storage The shared object of Sui Yield, it contains the treasury_cap. We need it to mint.
//   * @param token The Sui Coin, the sender wishes to stake
//   * @param validator_address The Sui Coin will be staked in this validator
//   * @param maturity The intended maturity of the bond
//   * @return (COIN<Sui Principal>, SuiYield)
//   */
//   public fun mint_stripped_bond(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     interest_sui_storage: &mut InterestSuiStorage,
//     sui_principal_storage: &mut SuiPrincipalStorage,
//     sui_yield_storage: &mut SuiYieldStorage,
//     token: Coin<SUI>,
//     validator_address: address,
//     maturity: u64,
//     ctx: &mut TxContext,
//   ):(SemiFungibleToken<SUI_PRINCIPAL>, SuiYield) {
//     // Ensure that users are using the correct version
//     assert_current_version(storage);

//     // It makes no sense to create an expired bond
//     assert!(maturity >= tx_context::epoch(ctx), errors::pool_outdated_maturity());

//     let token_amount = coin::value(&token);
//     mint_isui_logic(wrapper, storage, token, validator_address, ctx);


//     let sui_amount = if (is_whitelisted(storage, validator_address)) { 
//       token_amount
//     } else {
//       let validator_principal = linked_table::borrow(&storage.validators_table, validator_address).total_principal;
//       charge_stripped_bond_mint(
//         storage, 
//         interest_sui_storage, 
//         validator_principal, 
//         token_amount, 
//         ctx        
//       )
//     };

//     let shares_amount = rebase::to_base(&storage.pool, sui_amount, false);

//     // mint_isui_logic will update the pool
//     let sft_yield = sui_yield::mint( 
//       sui_yield_storage,
//       &storage.publisher,
//       (maturity as u256),
//       sui_amount,
//       shares_amount,
//       ctx
//     );

//     let sft_principal = sui_principal::mint(sui_principal_storage, &storage.publisher,  (maturity as u256), sui_amount, ctx);

//     emit(MintStrippedBond { 
//       sender: tx_context::sender(ctx), 
//       sui_amount, 
//       sui_principal_id: object::id(&sft_principal),
//       sui_yield_id: object::id(&sft_yield),
//       validator: validator_address 
//     });

//     (
//       sft_principal,
//       sft_yield
//     ) 
//   } 

//   // @dev This function allows the caller to call the stripped bond. It rquires both components to turn in to a bond
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to mint.
//   * @param sui_yield_storage The shared object of Sui Yield, it contains the treasury_cap. We need it to mint.
//   * @param sft_principal The residue portion of the bond
//   * @param sft_yield The yield portion of the bond
//   * @param maturity Back up maturity in case we missed an pool update call (should not happen)
//   * @param validator_address A validator to stake any leftover
//   * @param unstake_payload contains the data to select which validators to unstake
//   * @return Coin<SUI> in exchange for the Sui Principal burned
//   */
//   public fun call_bond(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     sui_principal_storage: &mut SuiPrincipalStorage,
//     sui_yield_storage: &mut SuiYieldStorage,
//     sft_principal: SemiFungibleToken<SUI_PRINCIPAL>,
//     sft_yield: SuiYield,
//     maturity: u64,
//     validator_address: address,
//     unstake_payload: vector<UnstakePayload>,
//     ctx: &mut TxContext,
//   ): Coin<SUI> {
//     // Ensure that users are using the correct version
//     assert_current_version(storage);

//     let slot = (sui_yield::slot(&sft_yield) as u64);
    
//     // They must be with the same slot
//     assert!((slot as u256) == sui_principal::slot(&sft_principal), errors::pool_mismatched_maturity());
//     // They must have the same value
//     assert!(sui_yield::value(&sft_yield) == sui_principal::value(&sft_principal), errors::pool_mismatched_values());

//     // Need to update the entire state of Sui/Sui Rewards once every epoch
//     // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
//     update_pool(wrapper, storage, ctx);

//     // Destroy both tokens
//     // Calculate how much Sui they are worth
//     let sui_amount = get_pending_yield_logic(storage, &sft_yield, maturity, ctx) + sui_principal::burn(sui_principal_storage, sft_principal);
//     sui_yield::burn(sui_yield_storage, sft_yield);

//     emit(CallBond { 
//       sui_amount, 
//       sender: tx_context::sender(ctx), 
//       maturity: slot,
//     });
//     // We need to update the pool
//     rebase::sub_elastic(&mut storage.pool, sui_amount, false);

//     // Unstake Sui
//     remove_staked_sui(wrapper, storage, sui_amount, unstake_payload,  validator_address, ctx)
//   }

//   // @dev This function burns Sui Principal in exchange for SUI at 1:1 rate
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param sui_principal_storage The shared object of Sui Principal, it contains the treasury_cap. We need it to burn Sui Principal
//   * @param token The Sui Principal, the sender wishes to burn
//   * @param validator_address The validator to re stake any remaining Sui if 
//   * @param unstake_payload contains the data to select which validators to unstake
//   * @return Coin<SUI> in exchange for the Sui Principal burned
//   */
//   public fun burn_sui_principal(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     sui_principal_storage: &mut SuiPrincipalStorage,
//     token: SemiFungibleToken<SUI_PRINCIPAL>,
//     validator_address: address,
//     unstake_payload: vector<UnstakePayload>,
//     ctx: &mut TxContext,
//   ): Coin<SUI> {
//     // Ensure that users are using the correct version
//     assert_current_version(storage);

//     assert!(tx_context::epoch(ctx) >= (sui_principal::slot(&token) as u64), errors::pool_bond_not_matured());

//     // Need to update the entire state of Sui/Sui Rewards once every epoch
//     // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
//     update_pool(wrapper, storage, ctx);

//     // 1 Sui Principal is always 1 SUI
//     // Burn the Sui Principal
//     let sui_amount = sui_principal::burn(sui_principal_storage, token);

//     // We need to update the pool
//     rebase::sub_elastic(&mut storage.pool, sui_amount, false);

//     emit(BurnSuiPrincipal { sui_amount, sender: tx_context::sender(ctx) });

//     // Unstake Sui
//     remove_staked_sui(wrapper, storage, sui_amount, unstake_payload,  validator_address, ctx)
//   }

//   // @dev This function allows a sender to claim his accrued yield
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param sui_yield_storage The Shared Object of Sui Yield
//   * @param sft_yield The SuiYield to burn in exchange for rewards
//   * @param validator_address The validator to re stake any remaining Sui if any
//   * @param unstake_payload contains the data to select which validators to unstake
//   * @param maturity The back up maturity in case we missed a {update_pool} call
//   * @return (SuiYield, Coin<SUI>) Returns the original token and the yield to the sender
//   */
//   public fun claim_yield(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     sui_yield_storage: &mut SuiYieldStorage,
//     sft_yield: SuiYield,
//     validator_address: address,
//     unstake_payload: vector<UnstakePayload>,
//     maturity: u64,
//     ctx: &mut TxContext,
//   ): (SuiYield, Coin<SUI>) {
//     // Ensure that users are using the correct version
//     assert_current_version(storage);

//     // Destroy both tokens
//     // Calculate how much Sui they are worth
//     let sui_amount = get_pending_yield(wrapper, storage, &sft_yield, maturity, ctx);
//     let is_zero_amount = sui_amount == 0;
//     // SuiYield has expired
//     if (!is_zero_amount) {
//       // Consider yield paid
//       sui_yield::add_rewards_paid(sui_yield_storage, &storage.publisher, &mut sft_yield, sui_amount);
//       // We need to update the pool
//       rebase::sub_elastic(&mut storage.pool, sui_amount, false);
//     };

//     emit(ClaimYield { sui_yield_id: object::id(&sft_yield), sui_amount, sender: tx_context::sender(ctx) });

//     // Unstake Sui
//     (
//       // We expire
//       if (tx_context::epoch(ctx) > (sui_yield::slot(&sft_yield) as u64)) { 
//           sui_yield::expire(sui_yield_storage, &storage.publisher,  sft_yield, ctx) 
//         } else { 
//           sft_yield 
//         }, 
//       if (is_zero_amount) { 
//           coin::zero(ctx) 
//         } else {
//           remove_staked_sui(wrapper, storage, sui_amount, unstake_payload, validator_address, ctx)
//         }
//     )
//   }

//   // ** Functions to handle Whitelist validators

//   // Checks if a validator is whitelisted (pays no fee)
//   /*
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param validator The address of the validator
//   * @return bool true if it is whitelisted
//   */
//   public fun is_whitelisted(storage: &PoolStorage, validator: address): bool {
//     vector::contains(&storage.whitelist_validators, &validator)
//   }

//   // Checks if a validator is whitelisted (pays no fee)
//   /*
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param validator The address of the validator
//   * @return bool true if it is whitelisted
//   */
//   public fun borrow_whitelist(storage: &PoolStorage): &vector<address> {
//     &storage.whitelist_validators
//   }

//   // Checks if a validator is whitelisted (pays no fee)
//   /*
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param validator The address of the validator
//   * @return bool true if it is whitelisted
//   */
//   public(friend) fun borrow_mut_whitelist(storage: &mut PoolStorage): &mut vector<address> {
//     &mut storage.whitelist_validators
//   }

//   // @dev This function safely updates the fees. It will throw if you pass values higher than 1e18.  
//   /*
//   * @param _: The AdminCap
//   * @param storage: The Pool Storage Shared Object (this module)
//   * @param base: The new base
//   * @param kink: The new kink
//   * @param jump The new jump
//   */
//   entry public fun update_fee(
//     _: &AdminCap,
//     storage: &mut PoolStorage, 
//     base: u128, 
//     kink: u128, 
//     jump: u128
//   ) {
//     let max = (one_sui_value() as u128);
//     // scalar represents 100% - the protocol does not allow a fee higher than that.
//     assert!(max >= base && max >= kink && max >= jump, errors::pool_invalid_fee());

//     // Update the fee values
//     set_fee(&mut storage.fee, base, kink, jump);

//     // Emit event
//     emit(NewFee { base, kink, jump });
//   }

//   // @dev This function allows the DAO to withdraw fees.
//   /*
//   * @param _: The AdminCap
//   * @param storage: The Pool Storage Shared Object (this module)
//   * @param amount: The value of fees to withdraw
//   * @return the fees in Coin<ISUI>
//   */
//   public fun withdraw_fees(
//     _: &AdminCap,
//     storage: &mut PoolStorage, 
//     amount: u64,
//     ctx: &mut TxContext
//   ): Coin<ISUI> {
    
//     // Emit the event
//     emit(DaoWithdraw {amount, sender: tx_context::sender(ctx) });

//     // Split the Fees and send the desired amount
//     coin::take(&mut storage.dao_balance, amount, ctx)
//   }

//   // ** CORE OPERATIONS

//   // @dev This function stakes Sui in a validator chosen by the sender and returns ISUI. 
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
//   * @param token The Sui Coin, the sender wishes to stake
//   * @param validator_address The Sui Coin will be staked in this validator
//   * @return Coin<ISUI> in exchange for the Sui deposited
//   */
//   fun mint_isui_logic(
//     wrapper: &mut SuiSystemState,
//     storage: &mut PoolStorage,
//     token: Coin<SUI>,
//     validator_address: address,
//     ctx: &mut TxContext,    
//   ): u64 {
//     // Save the value of Sui being staked in memory
//     let stake_value = coin::value(&token);

//     // Will save gas since the sui_system will throw
//     assert!(stake_value >= one_sui_value(), errors::pool_invalid_stake_amount());
    
//     // Need to update the entire state of Sui/Sui Rewards once every epoch
//     // The dev team will update once every 24 hours so users do not need to pay for this insane gas cost
//     update_pool(wrapper, storage, ctx);
  
//     // Stake Sui 
//     // We need to stake Sui before registering the validator to have access to the pool_id
//     let staked_sui = sui_system::request_add_stake_non_entry(wrapper, token, validator_address, ctx);

//     // Register the validator once in the linked_list
//     safe_register_validator(storage, staking_pool::pool_id(&staked_sui), validator_address, ctx);

//     // Save the validator data in memory
//     let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

//     // Store the Sui in storage
//     store_staked_sui(validator_data, staked_sui);

//     // Update the total principal in this entire module
//     storage.total_principal = storage.total_principal + stake_value;
//     // Update the total principal staked in this validator
//     validator_data.total_principal = validator_data.total_principal + stake_value;

//     // Update the Sui Pool 
//     // We round down to give the edge to the protocol
//     rebase::add_elastic(&mut storage.pool, stake_value, false)    
//   }

//   // @dev This function stores StakedSui with the same {activation_epoch} on a {LinkedTable}
//   /*
//   * @param validator_data: The Struct Data for the validator where we will deposit the Sui
//   * @param staked_sui: The StakedSui Object to store
//   */
//   fun store_staked_sui(validator_data: &mut ValidatorData, staked_sui: StakedSui) {
//       let activation_epoch = staking_pool::stake_activation_epoch(&staked_sui);

//       // If we already have Staked Sui with the same validator and activation epoch saved in the table, we will merge them
//       if (linked_table::contains(&validator_data.staked_sui_table, activation_epoch)) {
//         // Merge the StakedSuis
//         staking_pool::join_staked_sui(
//           linked_table::borrow_mut(&mut validator_data.staked_sui_table, activation_epoch), 
//           staked_sui
//         );
//       } else {
//         // If there is no StakedSui with the {activation_epoch} on our table, we add it.
//         linked_table::push_back(&mut validator_data.staked_sui_table, activation_epoch, staked_sui);
//       };
//   }
  

//   // @dev This function safely unstakes Sui
//   /*
//   * @param wrapper The Sui System Shared Object
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param amount The amount of Sui to  
//   * @param unstake_payload contains the data to select which validators to unstake
//   * @param validator_address The validator to restake
//   * @return Coin<SUI>
//   */
//   fun remove_staked_sui(
//       wrapper: &mut SuiSystemState, 
//       storage: &mut PoolStorage,
//       amount: u64,
//       unstake_payload: vector<UnstakePayload>,
//       validator_address: address,
//       ctx: &mut TxContext
//     ): Coin<SUI> {
    
//     // Create Zero Coin<SUI>, which we will join all Sui to return
//     let coin_sui_unstaked = coin::zero<SUI>(ctx);

//     let len = vector::length(&unstake_payload);
//     let i = 0;

//     while (len > i) {
//       let (validator_address, epoch_amount_vector) = unstake_utils::read_unstake_payload(vector::borrow(&unstake_payload, i));

//       let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);

//       let j = 0;
//       let l = vector::length(epoch_amount_vector);
//       while (l > j) {
//         let epoch_amount = vector::borrow(epoch_amount_vector, j);
//         let (activation_epoch, unstake_amount, split) = unstake_utils::read_epoch_amount(epoch_amount);

//         let staked_sui = linked_table::remove(&mut validator_data.staked_sui_table, activation_epoch);

//         let value = staking_pool::staked_sui_amount(&staked_sui);

//         if (split) {
//           // Split the Staked Sui -> Unstake -> Join with the Return Coin
//           coin::join(&mut coin_sui_unstaked, coin::from_balance(sui_system::request_withdraw_stake_non_entry(wrapper, staking_pool::split(&mut staked_sui, unstake_amount, ctx), ctx), ctx));

//           // Store the left over Staked Sui
//           store_staked_sui(validator_data, staked_sui);
//           // Update the validator data
//           validator_data.total_principal =  validator_data.total_principal - unstake_amount;
//           // We have unstaked enough          
//         } else {
//           // If we cannot split, we simply unstake the whole Staked Sui
//           coin::join(&mut coin_sui_unstaked, coin::from_balance(sui_system::request_withdraw_stake_non_entry(wrapper, staked_sui, ctx), ctx));
//           // Update the validator data
//           validator_data.total_principal =  validator_data.total_principal - value;          
//         };

//         j = j + 1;
//       };

//       i = i + 1;
//     };

//     // Check how much we unstaked
//     let total_value_unstaked = coin::value(&coin_sui_unstaked);

//     // Update the total principal
//     storage.total_principal = storage.total_principal - total_value_unstaked;
//     storage.total_activate_staked_sui = storage.total_activate_staked_sui - total_value_unstaked;

//     // If we unstaked more than the desired amount, we need to restake the different
//     if (total_value_unstaked > amount) {
//       let extra_value = total_value_unstaked - amount;
//       // Split the different in a new coin
//       let extra_coin_sui = coin::split(&mut coin_sui_unstaked, extra_value, ctx);
//       // Save the current dust in storage
//       let dust_value = balance::value(&storage.dust);

//       // If we have enough dust and extra sui to stake -> we stake and store in the table
//       if (extra_value + dust_value >= one_sui_value()) {
//         // Join Dust and extra coin
//         coin::join(&mut extra_coin_sui, coin::take(&mut storage.dust, dust_value, ctx));
//         let validator_data = linked_table::borrow_mut(&mut storage.validators_table, validator_address);
//         // Stake and store
//         store_staked_sui(validator_data, sui_system::request_add_stake_non_entry(wrapper, extra_coin_sui, validator_address, ctx));
//         validator_data.total_principal = validator_data.total_principal + extra_value;
//       } else {
//         // If we do not have enough to stake we save in the dust to be staked later on
//         coin::put(&mut storage.dust, extra_coin_sui);
//       };

//       storage.total_principal = storage.total_principal + extra_value;
//     };

//     // Return the Sui Coin
//     coin_sui_unstaked
//   }

//   // If there is a fee, it mints iSUi for the Admin
//   /*
//   * @param storage: The Pool Storage Shared Object (this module)
//   * @param interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
//   * @param validator_principal The amount of Sui principal deposited to the validator
//   * @param shares The amount of iSui being minted
//   * @return the amount of ISUI to mint to the sender
//   */
//   fun charge_isui_mint(
//     storage: &mut PoolStorage,
//     interest_sui_storage: &mut InterestSuiStorage,
//     validator_principal: u64,
//     shares: u64,
//     ctx: &mut TxContext
//     ): u64 {
    
//     // Find the fee % based on the validator dominance and fee parameters.  
//     let fee_amount = calculate_fee(storage, validator_principal, shares);

//     // If the fee is zero, there is nothing else to do
//     if (fee_amount == 0) return shares;

//     // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
//     coin::put(&mut storage.dao_balance, isui::mint(interest_sui_storage, &storage.publisher,  fee_amount, ctx));
//     // Return the shares amount to mint to the sender
//     shares - fee_amount
//   }

//     // If there is a fee, it mints iSUi for the Admin
//   /*
//   * @storage: The Pool Storage Shared Object (this module)
//   * @interest_sui_storage The shared object of ISUI, contains the treasury_cap. We need it to mint ISUI
//   * @validator_principal The amount of Sui principal deposited to the validator
//   * @amount The amount of Interest Sui Staked Amount being minted
//   * @return the amount of ISUI to mint to the sender
//   */
//   fun charge_stripped_bond_mint(
//     storage: &mut PoolStorage,
//     interest_sui_storage: &mut InterestSuiStorage,
//     validator_principal: u64,
//     amount: u64,
//     ctx: &mut TxContext
//     ): u64 {
    
//     // Find the fee % based on the validator dominance and fee parameters.  
//     let fee_amount = calculate_fee(storage, validator_principal, amount);

//     // If the fee is zero, there is nothing else to do
//     if (fee_amount == 0) return amount;

//     // Mint the ISUI for the DAO. We need to make sure the total supply of ISUI is consistent with the pool shares
//     coin::put(&mut storage.dao_balance, isui::mint(
//       interest_sui_storage, 
//       &storage.publisher,
//       rebase::to_base(&storage.pool, fee_amount, false), 
//       ctx
//     ));

//     // Return the shares amount to mint to the sender
//     amount - fee_amount
//   }

//   // @dev Adds a Validator to the linked_list
//   /*
//   * @storage: The Pool Storage Shared Object (this module)
//   * @staking_pool_id: The Id of the {validator_address} StakingPool
//   * @validator_address: The address of the validator
//   */
//   fun safe_register_validator(
//     storage: &mut PoolStorage,
//     staking_pool_id: ID,
//     validator_address: address,
//     ctx: &mut TxContext,    
//   ) {
//     // If the validator is already registered there is nmothing to do.
//     if (linked_table::contains(&storage.validators_table, validator_address)) return;
    
//     // Add the ValidatorData to the back of the list
//     linked_table::push_back(&mut storage.validators_table, validator_address, ValidatorData {
//         id: object::new(ctx),
//         staked_sui_table: linked_table::new(ctx),
//         staking_pool_id,
//         total_principal: 0
//       }); 
//   }

//   // @dev It returns the Sui value of the {sft}. it does not update the pool so careful!
//   /*
//   * @param storage The Pool Storage Shared Object (this module)
//   * @param sft The SuiYield
//   * @return u64 the exchange rate
//   */
//   fun get_pending_yield_logic(
//     storage: &PoolStorage, 
//     sft_yield: &SuiYield,
//     maturity: u64,
//     ctx: &mut TxContext
//   ): u64 {
//     let slot = (sui_yield::slot(sft_yield) as u64);

//     let (shares, principal, rewards_paid) = sui_yield::read_data(sft_yield);

//     let shares_value = if (tx_context::epoch(ctx) > slot) {
//       // If the user is getting the yield after maturity
//       // We need to find the exchange rate at maturity

//       // Check if the table has slot exchange rate
//       // If it does not we use the back up maturity value
//       let pool = if (linked_table::contains(&storage.pool_history, slot)) { 
//         linked_table::borrow(&storage.pool_history, slot)
//       } else {
//         // Back up maturity needs to be before the slot
//         assert!(slot > maturity, errors::pool_invalid_backup_maturity());
//         linked_table::borrow(&storage.pool_history, maturity)
//       };

//       rebase::to_elastic(pool, shares, false)
//     } else {
//       // If it is before maturity - we just read the pool
//       rebase::to_elastic(&storage.pool, shares, false)
//     };

//     let debt = rewards_paid + principal;

//     // Remove the principal to find out how many rewards this SFT has accrued
//     if (debt >= shares_value) {
//       0
//     } else {
//       shares_value - debt
//     }
//   }

//   // Core fee calculation logic
//   /*
//   * @storage: The Pool Storage Shared Object (this module)
//   * @validator_principal The amount of Sui principal deposited to the validator
//   * @amount The amount being minted
//   * @return u64 The fee amount
//   */
//   fun calculate_fee(
//     storage: &PoolStorage,
//     validator_principal: u64,
//     amount: u64,
//   ): u64 {
//     // Find the fee % based on the validator dominance and fee parameters.  
//     let fee = calculate_fee_percentage(
//       &storage.fee,
//       (validator_principal as u128),
//       (storage.total_principal as u128)
//     );

//     // Calculate fee
//     (fmul((amount as u128), fee) as u64)
//   }

//   // ** Version / Upgrade Functions
  
//   public fun version(storage: &PoolStorage): u64 { storage.version }

//   public fun start_upgrade(_: &AdminCap, storage: &PoolStorage, timelock: &mut VersionTimelock, ctx: &mut TxContext) {
//     v::start_upgrade(timelock, ctx);
//     emit(StartUpgrade { version: storage.version });
//   }
  
//   public fun upgrade(_: &AdminCap, storage: &mut PoolStorage, timelock: &mut VersionTimelock, ctx: &mut TxContext) {
//     v::upgrade(timelock, ctx);
//     // Bump the version so users are forced to use the new package
//     storage.version = version::current_version() + 1;
//     emit(FinishUpgrade {version: storage.version });
//   }

//   public fun cencel_upgrade(_: &AdminCap, timelock: &mut VersionTimelock) {
//     v::cancel_upgrade(timelock);
//     emit(CancelUpgrade {});
//   }
  
//   public fun is_current_version(storage: &PoolStorage): bool {
//     storage.version == version::current_version()
//   }
  
//   public fun assert_current_version(storage: &PoolStorage) {
//     assert!(is_current_version(storage), errors::old_version());
//   }

//  // ** SDK Functions
  
//  public fun read_pool_storage(storage: &PoolStorage): (&Rebase, u64, &LinkedTable<address, ValidatorData>, u64, &Fee, &Balance<ISUI>, &LinkedTable<u64, Rebase>) {
//     (
//       &storage.pool, 
//       storage.last_epoch, 
//       &storage.validators_table, 
//       storage.total_principal, 
//       &storage.fee, 
//       &storage.dao_balance,
//       &storage.pool_history
//     ) 
//   }

//   public fun read_validator_data(data: &ValidatorData): (&LinkedTable<u64, StakedSui>, u64) {
//     (
//       &data.staked_sui_table,
//       data.total_principal
//     )
//   }

//   // ** TEST FUNCTIONS

//   #[test_only]
//   public fun init_for_testing(ctx: &mut TxContext) {
//     init(POOL {}, ctx);
//   }

//   #[test_only]
//   public fun get_publisher_id(storage: &PoolStorage): ID {
//     object::id(&storage.publisher)
//   }
}