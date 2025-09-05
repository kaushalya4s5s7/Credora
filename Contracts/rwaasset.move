module rwaasset::rwaasset {
    use std::string;
    use issuerregistry::issuer_registry::{IssuerCap, IssuerRegistry, is_valid_issuer, issuer};

    public enum AssetType has store {
        RealEstate,
        Invoice,
        Gold,
        Stocks,
        CarbonCredit,
        Custom
    }

    public struct RWAAssetNFT has key, store {
        id: object::UID,
        issuer: address,
        metadata_uri: string::String,
        asset_type: AssetType,
        valuation: u64,
        maturity: std::option::Option<u64>,
        apy: std::option::Option<u64>,
    }

    public struct RWAAssetFT has key, store {
        id: object::UID,
        issuer: address,
        metadata_uri: string::String,
        asset_type: AssetType,
        total_supply: u64,
    }

    /// Mint NFT (with option fields)
    public entry fun mint_asset_nft(
        cap: &IssuerCap,
        metadata_uri: string::String,
        asset_type_index: u8,
        valuation: u64,
        has_maturity: bool,
        maturity: u64,
        has_apy: bool,
        apy: u64,
        registry: &IssuerRegistry,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(is_valid_issuer(registry, issuer(cap)), 0);

        let asset_type = if (asset_type_index == 0) {
            AssetType::RealEstate
        } else if (asset_type_index == 1) {
            AssetType::Invoice
        } else if (asset_type_index == 2) {
            AssetType::Gold
        } else if (asset_type_index == 3) {
            AssetType::Stocks
        } else if (asset_type_index == 4) {
            AssetType::CarbonCredit
        } else if (asset_type_index == 5) {
            AssetType::Custom
        } else {
            abort 42
        };

        let maturity_opt = if (has_maturity) {
            std::option::some(maturity)
        } else {
            std::option::none<u64>()
        };

        let apy_opt = if (has_apy) {
            std::option::some(apy)
        } else {
            std::option::none<u64>()
        };

        let nft = RWAAssetNFT {
            id: object::new(ctx),
            issuer: issuer(cap),
            metadata_uri,
            asset_type,
            valuation,
            maturity: maturity_opt,
            apy: apy_opt
        };
        transfer::transfer(nft, issuer(cap));
    }

    /// Mint FT
    public entry fun mint_asset_ft(
        cap: &IssuerCap,
        metadata_uri: string::String,
        asset_type_index: u8,
        total_supply: u64,
        registry: &IssuerRegistry,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(total_supply > 0, 1);
        assert!(is_valid_issuer(registry, issuer(cap)), 0);

        let asset_type = if (asset_type_index == 0) {
            AssetType::RealEstate
        } else if (asset_type_index == 1) {
            AssetType::Invoice
        } else if (asset_type_index == 2) {
            AssetType::Gold
        } else if (asset_type_index == 3) {
            AssetType::Stocks
        } else if (asset_type_index == 4) {
            AssetType::CarbonCredit
        } else if (asset_type_index == 5) {
            AssetType::Custom
        } else {
            abort 42
        };

        let ft = RWAAssetFT {
            id: object::new(ctx),
            issuer: issuer(cap),
            metadata_uri,
            asset_type,
            total_supply
        };
        transfer::transfer(ft, issuer(cap));
    }

    // === Public Getter Functions ===

    public fun nft_issuer(nft: &RWAAssetNFT): address {
        nft.issuer
    }

    public fun ft_issuer(ft: &RWAAssetFT): address {
        ft.issuer
    }
}
