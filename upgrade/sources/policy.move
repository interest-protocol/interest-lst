module interest_upgrade::policy {
    use std::vector;

    use sui::event::emit;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};  

    const SENTINEL_VALUE: u64 = 18446744073709551615;
    const TIME_DELAY: u64 = 2;

    // * Errors
    const ETooEarly: u64 = 0;

    struct UpgradeWrapper has key, store {
        id: UID,
        cap: UpgradeCap,
        init_epoch: u64,
        policy: u8,
        digest: vector<u8>
    }
    
    // * Events

    struct ImmutablePackage has copy, drop {
        id: ID
    }

    struct InitUpgrade has copy, drop {
        id: ID,
        policy: u8,
        digest: vector<u8>,
        epoch: u64
    }

    struct AuthorizeUpgrade has copy, drop {
        id: ID,
        policy: u8,
        digest: vector<u8>,
        epoch: u64
    }

    struct CancelUpgrade has copy, drop {
        id: ID
    }

    struct CommitUpgrade has copy, drop {
        id: ID
    }

    // @dev Wrap the Upgrade Cap to add a Time Lock
    public fun wrap_it(
        cap: UpgradeCap,
        ctx: &mut TxContext
    ): UpgradeWrapper {
        UpgradeWrapper {
            id: object::new(ctx),
            cap,
            init_epoch: SENTINEL_VALUE,
            policy: 0,
            digest: vector::empty()
        }
    }

    public fun init_upgrade(
        cap: &mut UpgradeWrapper,
        policy: u8,
        digest: vector<u8>,
        ctx: &mut TxContext        
    ) {
        let epoch = tx_context::epoch(ctx);
        emit(InitUpgrade { id: package::upgrade_package(&cap.cap), epoch, policy, digest });
        cap.policy = policy;
        cap.digest = digest;
        cap.init_epoch = tx_context::epoch(ctx);
    }

    public fun cancel_upgrade(cap: &mut UpgradeWrapper) {
        cap.init_epoch = SENTINEL_VALUE;
        cap.policy = 0;
        cap.digest = vector::empty();
        emit(CancelUpgrade { id:  package::upgrade_package(&cap.cap) });
    }

    public fun authorize_upgrade(
        cap: &mut UpgradeWrapper,
        ctx: &mut TxContext  
    ): UpgradeTicket {
        let epoch = tx_context::epoch(ctx);
        assert!(epoch >= cap.init_epoch + TIME_DELAY, ETooEarly);
        emit(AuthorizeUpgrade { id: package::upgrade_package(&cap.cap), epoch, policy: cap.policy, digest: cap.digest });
        package::authorize_upgrade(&mut cap.cap, cap.policy, cap.digest)
    }

    public fun commit_upgrade(cap: &mut UpgradeWrapper, receipt: UpgradeReceipt) {
        emit(CommitUpgrade { id: package::upgrade_package(&cap.cap)});
        cap.init_epoch = SENTINEL_VALUE;
        package::commit_upgrade(&mut cap.cap, receipt);
    }
    
    // @dev Make a package immutable
    public entry fun make_package_immutable(cap: UpgradeCap) {
        emit(ImmutablePackage { id: package::upgrade_package(&cap) });
        package::make_immutable(cap);
    }
}