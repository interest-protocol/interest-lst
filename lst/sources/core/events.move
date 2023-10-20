module interest_lst::events { 

  use sui::event::emit;

  friend interest_lst::interest_lst_inner_state;

  struct UpdateFund has copy, drop {
    principal: u64,
    rewards: u64
  }

  struct MintISui has copy, drop {
    sender: address,
    sui_amount: u64,
    isui_amount: u64,
    validator: address
  }

  struct BurnISui has copy, drop {
    sender: address,
    sui_amount: u64,
    isui_amount: u64,
  }

  struct MintStrippedBond has copy, drop {
    sender: address,
    sui_amount: u64,
    shares_amount: u64,
    validator: address
  }

  struct CallBond has copy, drop {
    sender: address,
    sui_amount: u64,
    maturity: u64    
  }

  struct BurnSuiPrincipal has copy, drop {
    sender: address,
    sui_amount: u64
  }

  struct ClaimYield has copy, drop {
    sender: address,
    sui_amount: u64,   
  }

  struct WhitelistValidators has copy, drop {
    list: vector<address>
  }

  public(friend) fun emit_update_fund(principal: u64, rewards: u64) {
    emit(UpdateFund { principal, rewards });  
  }

  public(friend) fun emit_mint_isui(
    sender: address,
    sui_amount: u64,
    isui_amount: u64,
    validator: address
  ) {
    emit(MintISui { sender, sui_amount, isui_amount, validator });
  }

  public(friend) fun emit_burn_isui(
    sender: address,
    sui_amount: u64,
    isui_amount: u64,
  ) {
    emit(BurnISui { sender, sui_amount, isui_amount });
  }

  public(friend) fun  emit_mint_stripped_bond(
    sender: address,
    sui_amount: u64,
    shares_amount: u64,
    validator: address    
  ) {
    emit(MintStrippedBond { sender, sui_amount, shares_amount, validator });
  }

  public(friend) fun emit_call_bond(
    sender: address,
    sui_amount: u64,
    maturity: u64  
  ) {
    emit(CallBond { sender, sui_amount, maturity });
  }

  public(friend) fun emit_burn_sui_principal(sender: address, sui_amount: u64) {
    emit(BurnSuiPrincipal { sender, sui_amount });
  }

  public(friend) fun emit_claim_yield(sender: address, sui_amount: u64) {
    emit(ClaimYield{ sender, sui_amount });
  }

  public(friend) fun emit_whitelist_validators(list: vector<address>) {
    emit(WhitelistValidators { list })  
  }
}