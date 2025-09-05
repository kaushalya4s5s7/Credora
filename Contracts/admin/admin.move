module admin::admin {
    // Error constants
    const E_NOT_ADMIN: u64 = 0;
    const E_ALREADY_PAUSED: u64 = 1;
    const E_ALREADY_ACTIVE: u64 = 2;

    // ===== Structs =====

    /// Registry for managing issuers
    public struct IssuerRegistry has key, store {
        id: object::UID,
    }

    /// Book for managing fungible token balances
    public struct FungibleBalanceBook has key, store {
        id: object::UID,
    }

    /// Capability object to restrict sensitive actions
    public struct AdminCap has key, store {
        id: object::UID,
        admin: address,
    }

    /// Platform-wide configuration and control state
    public struct PlatformState has key {
        id: object::UID,
        registry: IssuerRegistry,
        balance_book: FungibleBalanceBook,
        paused: bool,
    }

    // ===== Init Function =====

    /// Bootstrap the protocol: called once during deployment
    public entry fun initialize(ctx: &mut tx_context::TxContext) {
        let admin_addr = tx_context::sender(ctx);
        
        let admin_cap = AdminCap {
            id: object::new(ctx),
            admin: admin_addr,
        };

        let registry = IssuerRegistry {
            id: object::new(ctx),
        };
        
        let balance_book = FungibleBalanceBook {
            id: object::new(ctx),
        };

        let state = PlatformState {
            id: object::new(ctx),
            registry,
            balance_book,
            paused: false,
        };

        // Transfer objects
        transfer::transfer(admin_cap, admin_addr);
        transfer::share_object(state);
    }

    // ===== Entry Functions =====

    /// Pause marketplace + minting operations (emergency switch)
    public entry fun pause_platform(cap: &AdminCap, state: &mut PlatformState, ctx: &tx_context::TxContext) {
        assert!(is_admin(cap, ctx), E_NOT_ADMIN);
        assert!(!state.paused, E_ALREADY_PAUSED);
        state.paused = true;
    }

    /// Resume all operations
    public entry fun unpause_platform(cap: &AdminCap, state: &mut PlatformState, ctx: &tx_context::TxContext) {
        assert!(is_admin(cap, ctx), E_NOT_ADMIN);
        assert!(state.paused, E_ALREADY_ACTIVE);
        state.paused = false;
    }

    // ===== Helper Functions =====

    /// Check if the caller is admin
    fun is_admin(cap: &AdminCap, ctx: &tx_context::TxContext): bool {
        cap.admin == tx_context::sender(ctx)
    }

    // ===== Public Utility Functions =====

    /// Create a new issuer registry
        public entry fun new_registry(ctx: &mut tx_context::TxContext) {
            let registry = IssuerRegistry {
            id: object::new(ctx),
            };
            let sender = tx_context::sender(ctx);
            transfer::transfer(registry, sender);
        }


    /// Create a new balance book
    public entry fun new_balance_book(ctx: &mut tx_context::TxContext) {
        let book = FungibleBalanceBook {
        id: object::new(ctx),
        };
        let sender = tx_context::sender(ctx);
        transfer::transfer(book, sender);
    }


    // ===== Getter Functions =====

    /// Get reference to the issuer registry
    public fun get_registry(state: &PlatformState): &IssuerRegistry {
        &state.registry
    }

    /// Get reference to the balance book
    public fun get_balance_book(state: &PlatformState): &FungibleBalanceBook {
        &state.balance_book
    }

    /// Check if platform is paused
    public fun is_paused(state: &PlatformState): bool {
        state.paused
    }

    /// Get admin address from capability
    public fun admin_address(cap: &AdminCap): address {
        cap.admin
    }

    /// Assert the caller is admin (public for external modules)
    public fun assert_admin(cap: &AdminCap, ctx: &tx_context::TxContext) {
        assert!(cap.admin == tx_context::sender(ctx), E_NOT_ADMIN);
    }
}
