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
}