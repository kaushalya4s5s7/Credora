module marketplace::marketplace {
    use one::table::{Self, Table};
    use one::coin::{Self, Coin};
    use one::clock::{Clock};
    use one::oct::OCT;
    use rwaasset::rwaasset::{RWAAssetNFT, RWAAssetFT, nft_issuer, ft_issuer};
    use issuerregistry::issuer_registry::{IssuerRegistry, is_valid_issuer};
    use admin::admin::{AdminCap, assert_admin};

    const E_NOT_AUTHORIZED: u64 = 0;
    const E_NOT_SELLER: u64 = 3;
    const E_PAUSED: u64 = 4;
    const E_INVALID_PAYMENT: u64 = 5;
    const E_LISTING_NOT_FOUND: u64 = 6;
    const E_ASSET_NOT_FOUND: u64 = 7;
    const E_INSUFFICIENT_QUANTITY: u64 = 8;
    const E_INVALID_QUANTITY: u64 = 9;
    const E_ZERO_QUANTITY: u64 = 10;

    /// Main Marketplace object
    public struct Marketplace has key {
        id: object::UID,
        listings: Table<object::ID, MarketplaceListing>,
        ft_escrow: Table<object::ID, RWAAssetFT>,
        nft_escrow: Table<object::ID, RWAAssetNFT>,
        // Track FT ownership: asset_id -> (owner -> quantity)
        ft_ownership: Table<object::ID, Table<address, u64>>,
        paused: bool
    }

    /// Enhanced listing structure with quantity support
    public struct MarketplaceListing has copy, drop, store {
        asset_id: object::ID,
        is_nft: bool,
        seller: address,
        price_per_unit: u64, // Price per unit for FTs, total price for NFTs
        available_quantity: u64, // Available units for sale
        total_supply: u64, // Total supply (for FTs only)
        timestamp: u64
    }

    /// Initialize a new marketplace
    fun init(ctx: &mut tx_context::TxContext) {
        let marketplace = Marketplace {
            id: object::new(ctx),
            listings: table::new(ctx),
            ft_escrow: table::new(ctx),
            nft_escrow: table::new(ctx),
            ft_ownership: table::new(ctx),
            paused: false
        };
        transfer::share_object(marketplace);
    }

    /// Pause the marketplace (admin only)
    public entry fun pause(admin: &AdminCap, marketplace: &mut Marketplace, ctx: &tx_context::TxContext) {
        assert_admin(admin, ctx);
        marketplace.paused = true;
    }

    /// Unpause the marketplace (admin only)
    public entry fun unpause(admin: &AdminCap, marketplace: &mut Marketplace, ctx: &tx_context::TxContext) {
        assert_admin(admin, ctx);
        marketplace.paused = false;
    }

    /// List an NFT asset
    public entry fun list_asset_nft(
        marketplace: &mut Marketplace,
        issuer_registry: &IssuerRegistry,
        nft: RWAAssetNFT,
        price: u64,
        clock: &Clock,
        _ctx: &mut tx_context::TxContext
    ) {
        assert!(!marketplace.paused, E_PAUSED);
        assert!(is_valid_issuer(issuer_registry, nft_issuer(&nft)), E_NOT_AUTHORIZED);

        let asset_id = object::id(&nft);
        let ts = one::clock::timestamp_ms(clock);

        let listing = MarketplaceListing {
            asset_id,
            is_nft: true,
            seller: nft_issuer(&nft),
            price_per_unit: price,
            available_quantity: 1,
            total_supply: 1,
            timestamp: ts
        };

        table::add(&mut marketplace.nft_escrow, asset_id, nft);
        table::add(&mut marketplace.listings, asset_id, listing);
    }

    /// List FT with specific quantity and price per unit
    public entry fun list_asset_ft(
        marketplace: &mut Marketplace,
        issuer_registry: &IssuerRegistry,
        ft: RWAAssetFT,
        price_per_unit: u64,
        quantity_to_list: u64, // How many units to list for sale
        total_supply: u64, // Total supply of this FT (passed as parameter)
        clock: &Clock,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(!marketplace.paused, E_PAUSED);
        assert!(is_valid_issuer(issuer_registry, ft_issuer(&ft)), E_NOT_AUTHORIZED);
        assert!(price_per_unit > 0, E_INVALID_PAYMENT);
        assert!(quantity_to_list > 0 && quantity_to_list <= total_supply, E_INVALID_QUANTITY);

        let asset_id = object::id(&ft);
        let seller = ft_issuer(&ft);
        let ts = one::clock::timestamp_ms(clock);

        let listing = MarketplaceListing {
            asset_id,
            is_nft: false,
            seller,
            price_per_unit,
            available_quantity: quantity_to_list,
            total_supply,
            timestamp: ts
        };

        // Store the FT in escrow
        table::add(&mut marketplace.ft_escrow, asset_id, ft);
        table::add(&mut marketplace.listings, asset_id, listing);

        // Initialize ownership tracking
        let mut ownership_table = table::new(ctx);
        table::add(&mut ownership_table, seller, total_supply - quantity_to_list); // Seller keeps remaining
        table::add(&mut marketplace.ft_ownership, asset_id, ownership_table);
    }

    /// Buy specific quantity of FT tokens
    public entry fun buy_asset_ft(
        marketplace: &mut Marketplace,
        asset_id: object::ID,
        quantity: u64,
        mut payment: Coin<OCT>,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(!marketplace.paused, E_PAUSED);
        assert!(quantity > 0, E_ZERO_QUANTITY);
        assert!(table::contains(&marketplace.listings, asset_id), E_LISTING_NOT_FOUND);

        let listing = table::borrow_mut(&mut marketplace.listings, asset_id);
        assert!(!listing.is_nft, E_ASSET_NOT_FOUND);
        assert!(listing.available_quantity >= quantity, E_INSUFFICIENT_QUANTITY);

        let total_cost = listing.price_per_unit * quantity;
        assert!(coin::value(&payment) >= total_cost, E_INVALID_PAYMENT);

        // Calculate and distribute payment
        let protocol_fee = total_cost / 1000; // 0.1%
        let seller_share = total_cost - protocol_fee;
        let seller_coin = coin::split(&mut payment, seller_share, ctx);
        transfer::public_transfer(seller_coin, listing.seller);

        // Update available quantity
        listing.available_quantity = listing.available_quantity - quantity;

        // Update ownership tracking
        let buyer = tx_context::sender(ctx);
        let ownership_table = table::borrow_mut(&mut marketplace.ft_ownership, asset_id);
        
        if (table::contains(ownership_table, buyer)) {
            let current_balance = table::remove(ownership_table, buyer);
            table::add(ownership_table, buyer, current_balance + quantity);
        } else {
            table::add(ownership_table, buyer, quantity);
        };

        // If no more quantity available, remove listing but keep ownership tracking
        if (listing.available_quantity == 0) {
            let _removed_listing = table::remove(&mut marketplace.listings, asset_id);
        };

        // Return change to buyer
        transfer::public_transfer(payment, tx_context::sender(ctx));
    }

    /// Sell FT tokens back to marketplace (add to available quantity)
    public entry fun sell_asset_ft(
        marketplace: &mut Marketplace,
        asset_id: object::ID,
        quantity: u64,
        price_per_unit: u64,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(!marketplace.paused, E_PAUSED);
        assert!(quantity > 0, E_ZERO_QUANTITY);
        assert!(price_per_unit > 0, E_INVALID_PAYMENT);
        
        let seller = tx_context::sender(ctx);
        assert!(table::contains(&marketplace.ft_ownership, asset_id), E_ASSET_NOT_FOUND);
        
        let ownership_table = table::borrow_mut(&mut marketplace.ft_ownership, asset_id);
        assert!(table::contains(ownership_table, seller), E_NOT_AUTHORIZED);
        
        let current_balance = table::remove(ownership_table, seller);
        assert!(current_balance >= quantity, E_INSUFFICIENT_QUANTITY);

        // Update seller's balance
        let remaining_balance = current_balance - quantity;
        if (remaining_balance > 0) {
            table::add(ownership_table, seller, remaining_balance);
        };

        // Check if listing already exists
        if (table::contains(&marketplace.listings, asset_id)) {
            // Update existing listing
            let listing = table::borrow_mut(&mut marketplace.listings, asset_id);
            // Only allow if same price per unit (or implement price matching logic)
            assert!(listing.price_per_unit == price_per_unit, E_INVALID_PAYMENT);
            listing.available_quantity = listing.available_quantity + quantity;
        } else {
            // Create new listing - we need the original FT data
            assert!(table::contains(&marketplace.ft_escrow, asset_id), E_ASSET_NOT_FOUND);
            
            let listing = MarketplaceListing {
                asset_id,
                is_nft: false,
                seller,
                price_per_unit,
                available_quantity: quantity,
                total_supply: 0, // We'd need to track this or get from FT
                timestamp: 0 // We'd need clock parameter
            };
            
            table::add(&mut marketplace.listings, asset_id, listing);
        };
    }

    /// Buy complete asset (backward compatibility)
    public entry fun buy_asset(
        marketplace: &mut Marketplace,
        asset_id: object::ID,
        mut payment: Coin<OCT>,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(!marketplace.paused, E_PAUSED);
        assert!(table::contains(&marketplace.listings, asset_id), E_LISTING_NOT_FOUND);

        let listing = table::remove(&mut marketplace.listings, asset_id);
        
        let total_cost = if (listing.is_nft) {
            listing.price_per_unit
        } else {
            listing.price_per_unit * listing.available_quantity
        };
        
        assert!(coin::value(&payment) >= total_cost, E_INVALID_PAYMENT);

        let protocol_fee = total_cost / 1000; // 0.1%
        let seller_share = total_cost - protocol_fee;
        let seller_coin = coin::split(&mut payment, seller_share, ctx);
        transfer::public_transfer(seller_coin, listing.seller);

        if (listing.is_nft) {
            assert!(table::contains(&marketplace.nft_escrow, asset_id), E_ASSET_NOT_FOUND);
            let nft = table::remove(&mut marketplace.nft_escrow, asset_id);
            transfer::public_transfer(nft, tx_context::sender(ctx));
        } else {
            // For FT, transfer ownership of all available quantity
            let buyer = tx_context::sender(ctx);
            let ownership_table = table::borrow_mut(&mut marketplace.ft_ownership, asset_id);
            
            if (table::contains(ownership_table, buyer)) {
                let current_balance = table::remove(ownership_table, buyer);
                table::add(ownership_table, buyer, current_balance + listing.available_quantity);
            } else {
                table::add(ownership_table, buyer, listing.available_quantity);
            };
        };

        transfer::public_transfer(payment, tx_context::sender(ctx));
    }

    /// Cancel a listing (seller only)
    public entry fun cancel_listing(
        marketplace: &mut Marketplace,
        asset_id: object::ID,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(table::contains(&marketplace.listings, asset_id), E_LISTING_NOT_FOUND);
        let listing = table::remove(&mut marketplace.listings, asset_id);
        assert!(tx_context::sender(ctx) == listing.seller, E_NOT_SELLER);

        if (listing.is_nft) {
            assert!(table::contains(&marketplace.nft_escrow, asset_id), E_ASSET_NOT_FOUND);
            let nft = table::remove(&mut marketplace.nft_escrow, asset_id);
            transfer::public_transfer(nft, listing.seller);
        } else {
            // For FT, return the listed quantity to seller's balance
            let ownership_table = table::borrow_mut(&mut marketplace.ft_ownership, asset_id);
            if (table::contains(ownership_table, listing.seller)) {
                let current_balance = table::remove(ownership_table, listing.seller);
                table::add(ownership_table, listing.seller, current_balance + listing.available_quantity);
            } else {
                table::add(ownership_table, listing.seller, listing.available_quantity);
            };
        };
    }

    /// Get FT balance for an address (view function)
    public fun get_ft_balance(marketplace: &Marketplace, asset_id: object::ID, owner: address): u64 {
        if (!table::contains(&marketplace.ft_ownership, asset_id)) {
            return 0
        };
        
        let ownership_table = table::borrow(&marketplace.ft_ownership, asset_id);
        if (table::contains(ownership_table, owner)) {
            *table::borrow(ownership_table, owner)
        } else {
            0
        }
    }

    /// Withdraw FT tokens (remove from marketplace and transfer original FT if fully owned)
    public entry fun withdraw_ft(
        marketplace: &mut Marketplace,
        asset_id: object::ID,
        ctx: &mut tx_context::TxContext
    ) {
        let owner = tx_context::sender(ctx);
        assert!(table::contains(&marketplace.ft_ownership, asset_id), E_ASSET_NOT_FOUND);
        
        let ownership_table = table::borrow_mut(&mut marketplace.ft_ownership, asset_id);
        assert!(table::contains(ownership_table, owner), E_NOT_AUTHORIZED);
        
        let balance = table::remove(ownership_table, owner);
        
        // If owner owns the entire supply and the original FT is still in escrow, transfer it
        if (table::contains(&marketplace.ft_escrow, asset_id)) {
            let _ft = table::borrow(&marketplace.ft_escrow, asset_id);
            // We'd need to check if balance equals total supply
            // For simplicity, let's assume they can withdraw if they have any balance
            
            if (balance > 0) {
                // In a complete implementation, you might:
                // 1. Create a new FT token representing their balance
                // 2. Or maintain the ownership system and let them trade within marketplace
                // For now, we'll just update their balance back
                table::add(ownership_table, owner, balance);
            };
        };
    }

    /// Get all asset IDs where the user has FT balance (view function)
    public fun get_user_ft_assets(_marketplace: &Marketplace, _owner: address): vector<object::ID> {
        let result = vector::empty<object::ID>();
        // Note: This is a simplified version. In practice, you might want to maintain 
        // a reverse index or emit events to track user holdings efficiently.
        // For now, this function serves as a placeholder for the interface.
        result
    }
}
