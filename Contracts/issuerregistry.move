module issuerregistry::issuer_registry {

    /// Public struct to be accessed by other modules
    public struct IssuerRegistry has key, store {
        id: object::UID,
        admin: address,
        issuers: vector<IssuerInfo>,
    }

    /// Public struct used by rwa_asset module for access control i.e. Capability object given to a verified issuer
    public struct IssuerCap has key{
        id: object::UID,
        issuer: address,
    }

      // Public accessor for the issuer address in IssuerCap
     public fun issuer(cap: &IssuerCap): address {
         cap.issuer
     }

    /// Issuer metadata
    public struct IssuerInfo has copy, drop, store {
        issuer: address,
        name: vector<u8>,
        metadata_uri: vector<u8>, // IPFS/HTTP URI with legal + KYC details
        active: bool,
    }

    /// Create the issuer registry (only once)
    public entry fun init_registry(ctx: &mut tx_context::TxContext) {
    let registry = IssuerRegistry {
        id: object::new(ctx),
        admin: tx_context::sender(ctx),
        issuers: vector::empty<IssuerInfo>(),
    };
    transfer::transfer(registry, tx_context::sender(ctx));
    }


    /// Admin-only: Add new verified issuer
    public entry fun add_issuer(
        registry: &mut IssuerRegistry,
        issuer: address,
        name: vector<u8>,
        metadata_uri: vector<u8>,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, 0);
        let info = IssuerInfo {
            issuer,
            name,
            metadata_uri,
            active: true,
        };
        vector::push_back(&mut registry.issuers, info);
    }

    /// Admin-only: Deactivate an issuer
    public entry fun deactivate_issuer(
        registry: &mut IssuerRegistry,
        issuer: address,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, 1);
        let len = vector::length(&registry.issuers);
        let mut i = 0;
        while (i < len) {
            let info = vector::borrow_mut(&mut registry.issuers, i);
            if (info.issuer == issuer) {
                info.active = false;
                return
            };
            i = i + 1;
        }
    }

    /// Admin-only: Issue an IssuerCap to the verified issuer
    public entry fun issue_cap(
        registry: &IssuerRegistry,
        issuer: address,
        ctx: &mut tx_context::TxContext
        ) {
        assert!(tx_context::sender(ctx) == registry.admin, 2);
        assert!(is_valid_issuer(registry, issuer), 3);
        let cap = IssuerCap { id: object::new(ctx), issuer };
        transfer::transfer(cap, issuer);
    }


    /// Public: check if address is active issuer
    public fun is_valid_issuer(
        registry: &IssuerRegistry,
        addr: address
    ): bool {
        let len = vector::length(&registry.issuers);
        let mut i = 0;
        while (i < len) {
            let info = vector::borrow(&registry.issuers, i);
            if (info.issuer == addr && info.active) {
                return true
            };
            i = i + 1;
        };
        false
    }
}
