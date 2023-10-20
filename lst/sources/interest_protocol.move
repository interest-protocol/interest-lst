// Interest Protocol DAO
module interest_lst::interest_protocol {

  use sui::tx_context::TxContext;
  use sui::transfer::public_share_object;

  use suitears::dao::create_with_treasury;

  use interest_lst::ipx::IPX;

  const VOTING_DELAY: u64 = 259_200_000; // Three days - Time delay between proposal creation and voting
  const VOTING_PERIOD: u64 = 1_209_600_000; // 2 Weeks Voters have two weeks to vote
  const MIN_VOTING_QUORUM_RATE: u128 = 600_000_000; // 60% out of the total votes need to be in agreement to pass
  const MIN_ACTION_DELAY: u64 = 259_200_000; // Three days - A proposal can be excuted three days after its end period
  const MIN_QUORUM_VOTES: u64 = 50_000_000_000_000_000; // Assuming IPX will have 1 billion total supply. 5% of voters need to participate

  // OTW
  struct INTEREST_PROTOCOL has drop {}

  fun init(otw: INTEREST_PROTOCOL, ctx: &mut TxContext) {
   let (dao, treasury) = create_with_treasury<INTEREST_PROTOCOL, IPX>(
    otw,
    VOTING_DELAY,
    VOTING_PERIOD,
    MIN_VOTING_QUORUM_RATE,
    MIN_ACTION_DELAY,
    MIN_QUORUM_VOTES,
    true,
    ctx
   );

   public_share_object(dao);
   public_share_object(treasury);
  }
}