// TODO# 1: Define Module and Marketplace Address
address 0xa256fddba13780914e70b6f74cf24af7548e796ad8dcbf331c85c93327f99ec4{

    module NFTMarketplace {
        use std::signer;
        use std::vector;
        use std::string::String;
        use std::option::{Self, Option};
        use aptos_framework::coin::{Self, Coin};
        use aptos_framework::aptos_coin::AptosCoin;
        use aptos_framework::timestamp;
        use aptos_framework::event;
        use aptos_framework::table::{Self, Table};
        use aptos_token::token;



        // TODO# 2: Define NFT Structure
        struct NFT has store, key {
            id: u64,
            owner: address,
            name: vector<u8>,
            description: vector<u8>,
            uri: vector<u8>,
            price: u64,
            for_sale: bool,
            rarity: u8,
            // New auction fields
            is_auction: bool,
            auction_end: u64,
            highest_bidder: address,
            highest_bid: u64,
            min_bid_increment: u64
        }

        // TODO# 3: Define Marketplace Structure
        struct Marketplace has key {
            nfts: vector<NFT>
        }
        
        // TODO# 4: Define ListedNFT Structure
         struct ListedNFT has copy, drop {
            id: u64,
            price: u64,
            rarity: u8
        }

        // New Bid structure
        struct Bid has store, drop {
            bidder: address,
            amount: u64,
            timestamp: u64
        }

        struct GiftMessage has store, drop {
            message: vector<u8>,
            from: address,
            timestamp: u64
        }

        struct TradeOffer has store, key {
            id: u64,
            from_address: address,
            to_address: address,
            offered_nft_ids: vector<u64>,
            requested_nft_ids: vector<u64>,
            message: vector<u8>,
            status: u8, // 0: pending, 1: accepted, 2: rejected
            timestamp: u64
        }

        struct TransferHistory has store, key {
            transfers: vector<Transfer>
        }

        struct Transfer has store, drop {
            nft_id: u64,
            from_address: address,
            to_address: address,
            timestamp: u64,
            is_gift: bool,
            gift_message: Option<GiftMessage>
        }

        #[event]
        struct OfferAccepted has drop, store {
            nft_id: u64,
            offer_id: u64,
            buyer: address,
            seller: address,
            amount: u64
        }

        #[event]
        struct CounterOfferCreated has drop, store {
            nft_id: u64,
            original_offer_id: u64,
            counter_offer_id: u64,
            buyer: address,
            seller: address,
            amount: u64
        }

        struct MarketplaceData has key {
            listings: Table<u64, Listing>,
            offers: Table<u64, Offer>,
            offer_escrow: Coin<AptosCoin>,
            next_offer_id: u64
        }

        struct Offer has store, drop {
            nft_id: u64,
            buyer: address,
            amount: u64,
            expiration: u64,
            status: u8
        }

        #[event]
        struct OfferCanceled has drop, store {
            nft_id: u64,
            offer_id: u64,
            buyer: address
        }


        struct Listing has store, drop {
            seller: address,
            creator: address,
            collection: String,
            name: String
        }


        // Constants
        const MARKETPLACE_FEE_PERCENT: u64 = 2;
        const MIN_AUCTION_DURATION: u64 = 20; // 20 seconds
        const DEFAULT_MIN_BID_INCREMENT: u64 = 100; // Default minimum bid increment
        const COUNTER_OFFER_DURATION: u64 = 86400;
        const ERROR_INSUFFICIENT_FUNDS: u64 = 14;
        const ERROR_NOT_OWNER: u64 = 15;
        const ERROR_NFT_NOT_LISTED: u64 = 16;
        const OFFER_STATUS_PENDING: u8 = 0;
        const OFFER_STATUS_ACCEPTED: u8 = 1;
        const OFFER_STATUS_REJECTED: u8 = 2;
        const OFFER_STATUS_COUNTER: u8 = 3;
        const OFFER_STATUS_COUNTERED: u8 = 4;


        // Error codes
        const ENOT_OWNER: u64 = 100;
        const EALREADY_LISTED: u64 = 101;
        const EINVALID_PRICE: u64 = 102;
        const EAUCTION_ACTIVE: u64 = 103;
        const EAUCTION_ENDED: u64 = 104;
        const EBID_TOO_LOW: u64 = 105;
        const EAUCTION_NOT_ENDED: u64 = 106;
        const EINVALID_RECIPIENT: u64 = 107;
        const EINVALID_TRADE_OFFER: u64 = 108;
        const ERROR_OFFER_NOT_FOUND: u64 = 11;
        const ERROR_OFFER_NOT_PENDING: u64 = 12;
        const ERROR_OFFER_EXPIRED: u64 = 13;
        const ERROR_ALREADY_INITIALIZED: u64 = 1001;


        // TODO# 6: Initialize Marketplace  

        public entry fun initialize(account: &signer) {
            let marketplace = Marketplace {
                nfts: vector::empty<NFT>()
            };
            move_to(account, marketplace);
        }
              
        public entry fun initialize_marketplace(
            marketplace: &signer
        ) {
            let addr = signer::address_of(marketplace);

            // Ensure MarketplaceData isn't already initialized
            assert!(exists<MarketplaceData>(addr) == false, ERROR_ALREADY_INITIALIZED);

            // Initialize the resource
            move_to(
                marketplace,
                MarketplaceData {
                    offer_escrow: coin::zero<AptosCoin>(), // Initialize empty escrow
                    offers: table::new<u64, Offer>(),      // Initialize empty offers table
                    listings: table::new<u64, Listing>(),  // Initialize empty listings table (or appropriate type)
                    next_offer_id: 0                       // Start with offer ID 0
                }
            );
        }


        // TODO# 7: Check Marketplace Initialization
        #[view]
        public fun is_marketplace_initialized(marketplace_addr: address): bool {
            exists<Marketplace>(marketplace_addr)
        }


        // TODO# 8: Mint New NFT
        public entry fun mint_nft(account: &signer, name: vector<u8>, description: vector<u8>, uri: vector<u8>, rarity: u8) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(signer::address_of(account));
            let nft_id = vector::length(&marketplace.nfts);
            
            let new_nft = NFT {
                id: nft_id,
                owner: signer::address_of(account),
                name,
                description,
                uri,
                price: 0,
                for_sale: false,
                rarity,
                // Initialize auction fields
                is_auction: false,
                auction_end: 0,
                highest_bidder: @0x0,
                highest_bid: 0,
                min_bid_increment: DEFAULT_MIN_BID_INCREMENT
            };
            vector::push_back(&mut marketplace.nfts, new_nft);
        }


        // TODO# 9: View NFT Details
        #[view]
        public fun get_nft_details(marketplace_addr: address, nft_id: u64): (u64, address, vector<u8>, vector<u8>, vector<u8>, u64, bool, u8) acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);

            (nft.id, nft.owner, nft.name, nft.description, nft.uri, nft.price, nft.for_sale, nft.rarity)
        }

        
        // TODO# 10: List NFT for Sale
        public entry fun list_for_sale(account: &signer, marketplace_addr: address, nft_id: u64, price: u64) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 100); // Caller is not the owner
            assert!(!nft_ref.for_sale, 101); // NFT is already listed
            assert!(price > 0, 102); // Invalid price

            nft_ref.for_sale = true;
            nft_ref.price = price;
        }


        // TODO# 11: Update NFT Price
        public entry fun set_price(account: &signer, marketplace_addr: address, nft_id: u64, price: u64) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 200); // Caller is not the owner
            assert!(price > 0, 201); // Invalid price

            nft_ref.price = price;
        }


        // TODO# 12: Purchase NFT
        public entry fun purchase_nft(account: &signer, marketplace_addr: address, nft_id: u64, payment: u64) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.for_sale, 400); // NFT is not for sale
            assert!(payment >= nft_ref.price, 401); // Insufficient payment

            // Calculate marketplace fee
            let fee = (nft_ref.price * MARKETPLACE_FEE_PERCENT) / 100;
            let seller_revenue = payment - fee;

            // Transfer payment to the seller and fee to the marketplace
            coin::transfer<AptosCoin>(account, marketplace_addr, seller_revenue);
            coin::transfer<AptosCoin>(account, signer::address_of(account), fee);

            // Transfer ownership
            nft_ref.owner = signer::address_of(account);
            nft_ref.for_sale = false;
            nft_ref.price = 0;
        }


        // TODO# 13: Check if NFT is for Sale
        #[view]
        public fun is_nft_for_sale(marketplace_addr: address, nft_id: u64): bool acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.for_sale
        }


        // TODO# 14: Get NFT Price
        #[view]
        public fun get_nft_price(marketplace_addr: address, nft_id: u64): u64 acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.price
        }


        // TODO# 15: Transfer Ownership
        public entry fun transfer_ownership(account: &signer, marketplace_addr: address, nft_id: u64, new_owner: address) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 300); // Caller is not the owner
            (nft_ref.owner != new_owner, 301); // Prevent transfer to the same owner

            // Update NFT ownership and reset its for_sale status and price
            nft_ref.owner = new_owner;
            nft_ref.for_sale = false;
            nft_ref.price = 0;
        }


        // TODO# 16: Retrieve NFT Owner
        #[view]
        public fun get_owner(marketplace_addr: address, nft_id: u64): address acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.owner
        }


        // TODO# 17: Retrieve NFTs for Sale
        #[view]
        public fun get_all_nfts_for_owner(marketplace_addr: address, owner_addr: address, limit: u64, offset: u64): vector<u64> acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft_ids = vector::empty<u64>();

            let nfts_len = vector::length(&marketplace.nfts);
            let end = min(offset + limit, nfts_len);
            let mut_i = offset;
            while (mut_i < end) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.owner == owner_addr) {
                    vector::push_back(&mut nft_ids, nft.id);
                };
                mut_i = mut_i + 1;
            };

            nft_ids
        }
 

        // TODO# 18: Retrieve NFTs for Sale
        #[view]
        public fun get_all_nfts_for_sale(marketplace_addr: address, limit: u64, offset: u64): vector<ListedNFT> acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nfts_for_sale = vector::empty<ListedNFT>();

            let nfts_len = vector::length(&marketplace.nfts);
            let end = min(offset + limit, nfts_len);
            let mut_i = offset;
            while (mut_i < end) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.for_sale) {
                    let listed_nft = ListedNFT { id: nft.id, price: nft.price, rarity: nft.rarity };
                    vector::push_back(&mut nfts_for_sale, listed_nft);
                };
                mut_i = mut_i + 1;
            };

            nfts_for_sale
        }


        // TODO# 19: Define Helper Function for Minimum Value
        // Helper function to find the minimum of two u64 numbers
        public fun min(a: u64, b: u64): u64 {
            if (a < b) { a } else { b }
        }


        // TODO# 20: Retrieve NFTs by Rarity
        // New function to retrieve NFTs by rarity
        #[view]
        public fun get_nfts_by_rarity(marketplace_addr: address, rarity: u8): vector<u64> acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft_ids = vector::empty<u64>();

            let nfts_len = vector::length(&marketplace.nfts);
            let mut_i = 0;
            while (mut_i < nfts_len) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.rarity == rarity) {
                    vector::push_back(&mut nft_ids, nft.id);
                };
                mut_i = mut_i + 1;
            };

            nft_ids
        }

        public entry fun clear_marketplace(marketplace_addr: address) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            while (!vector::is_empty(&marketplace.nfts)) {
                let nft = vector::pop_back(&mut marketplace.nfts);
                // Store or handle the NFT appropriately
                let NFT { id: _, owner: _, name: _, description: _, uri: _, price: _, for_sale: _, rarity: _, is_auction: _, auction_end: _, highest_bid: _, highest_bidder: _, min_bid_increment: _ } = nft;
            };
        }


        public entry fun reset_marketplace(account: &signer) acquires Marketplace, MarketplaceData {
            let marketplace_addr = signer::address_of(account);
            
            // Move out and destructure Marketplace
            let Marketplace { nfts } = move_from<Marketplace>(marketplace_addr);
            
            // Clean up NFTs vector
            while (!vector::is_empty(&mut nfts)) {
                let nft = vector::pop_back(&mut nfts);
                let NFT { id: _, owner: _, name: _, description: _, uri: _, price: _, for_sale: _, rarity: _, is_auction: _, auction_end: _, highest_bid: _, highest_bidder: _, min_bid_increment: _ } = nft;
            };
            vector::destroy_empty(nfts);
            
            // Get next_offer_id before destructuring
            let next_offer_id = borrow_global<MarketplaceData>(marketplace_addr).next_offer_id;
            
            // Move out MarketplaceData and clean up tables
            let MarketplaceData { listings, offers, offer_escrow, next_offer_id: _ } = move_from<MarketplaceData>(marketplace_addr);
            
            // Clean up tables by removing all entries up to next_offer_id
            let i = 0;
            while (i < next_offer_id) {
                if (table::contains(&listings, i)) {
                    table::remove(&mut listings, i);
                };
                if (table::contains(&offers, i)) {
                    table::remove(&mut offers, i);
                };
                i = i + 1;
            };
            
            // Destroy coin
            coin::destroy_zero(offer_escrow);
            
            // Initialize fresh marketplace with cleaned tables
            move_to(account, Marketplace {
                nfts: vector::empty()
            });
            
            move_to(account, MarketplaceData {
                listings,
                offers,
                offer_escrow: coin::zero<AptosCoin>(),
                next_offer_id: 0
            });
        }


        // New Auction Functions

        public entry fun create_auction(
            account: &signer,
            marketplace_addr: address,
            nft_id: u64,
            starting_price: u64,
            duration: u64,
            min_bid_increment: u64
        ) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);
            
            assert!(nft_ref.owner == signer::address_of(account), ENOT_OWNER);
            assert!(!nft_ref.for_sale && !nft_ref.is_auction, EALREADY_LISTED);
            assert!(starting_price > 0, EINVALID_PRICE);
            assert!(duration >= MIN_AUCTION_DURATION, EINVALID_PRICE);

            nft_ref.is_auction = true;
            nft_ref.price = starting_price;
            nft_ref.auction_end = timestamp::now_seconds() + duration;
            nft_ref.highest_bidder = @0x0;
            nft_ref.highest_bid = starting_price;  // Set initial highest bid to starting price
            nft_ref.min_bid_increment = min_bid_increment;
        }


        public entry fun place_bid(
            account: &signer,
            marketplace_addr: address,
            nft_id: u64,
            bid_amount: u64
        ) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);
            
            assert!(nft_ref.is_auction, EAUCTION_ACTIVE);
            assert!(timestamp::now_seconds() < nft_ref.auction_end, EAUCTION_ENDED);
            assert!(bid_amount >= nft_ref.price + nft_ref.min_bid_increment, EBID_TOO_LOW);

            // Refund previous highest bidder if exists
            if (nft_ref.highest_bidder != @0x0) {
                coin::transfer<AptosCoin>(account, nft_ref.highest_bidder, nft_ref.highest_bid);
            };

            // Update auction state
            nft_ref.highest_bidder = signer::address_of(account);
            nft_ref.highest_bid = bid_amount;

            // Transfer bid amount to marketplace escrow
            coin::transfer<AptosCoin>(account, marketplace_addr, bid_amount);
        }

        public entry fun end_auction(
            account: &signer,
            marketplace_addr: address,
            nft_id: u64
        ) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);
            
            // Verify auction state
            assert!(nft_ref.is_auction, EAUCTION_ACTIVE);
            assert!(timestamp::now_seconds() >= nft_ref.auction_end, EAUCTION_NOT_ENDED);

            // Handle successful auction
            if (nft_ref.highest_bidder != @0x0) {
                let previous_owner = nft_ref.owner;
                
                // Transfer funds
                let fee = (nft_ref.highest_bid * MARKETPLACE_FEE_PERCENT) / 100;
                let seller_revenue = nft_ref.highest_bid - fee;
                
                coin::transfer<AptosCoin>(account, previous_owner, seller_revenue);
                coin::transfer<AptosCoin>(account, marketplace_addr, fee);
                
                // Update ownership
                nft_ref.owner = nft_ref.highest_bidder;
            };

            // Reset NFT state completely
            nft_ref.is_auction = false;
            nft_ref.for_sale = false;
            nft_ref.highest_bidder = @0x0;
            nft_ref.highest_bid = 0;
            nft_ref.auction_end = 0;
            nft_ref.price = 0;
        }


        // View functions for auctions
        #[view]
        public fun get_auction_info(marketplace_addr: address, nft_id: u64): (bool, u64, address, u64, u64) acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            
            (
                nft.is_auction,
                nft.auction_end,
                nft.highest_bidder,
                nft.highest_bid,
                nft.min_bid_increment
            )
        }

        #[view]
        public fun is_auction_active(marketplace_addr: address, nft_id: u64): bool acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            
            nft.is_auction && timestamp::now_seconds() < nft.auction_end
        }

        // New transfer functions

        public entry fun transfer_nft_with_message(
            from: &signer,
            marketplace_addr: address,
            nft_id: u64,
            to_address: address,
            message: vector<u8>,
            is_gift: bool
        ) acquires Marketplace, TransferHistory {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);
            
            assert!(nft_ref.owner == signer::address_of(from), ENOT_OWNER);
            assert!(to_address != @0x0, EINVALID_RECIPIENT);
            
            let from_addr = signer::address_of(from);
            
            // Create gift message if it's a gift
            let gift_msg = if (is_gift) {
                option::some(GiftMessage {
                    message,
                    from: from_addr,
                    timestamp: timestamp::now_seconds()
                })
            } else {
                option::none()
            };
            
            // Update NFT ownership
            nft_ref.owner = to_address;
            nft_ref.for_sale = false;
            nft_ref.price = 0;
            
            // Record transfer in history
            if (!exists<TransferHistory>(marketplace_addr)) {
                move_to(from, TransferHistory { transfers: vector::empty() });
            };
            
            let history = borrow_global_mut<TransferHistory>(marketplace_addr);
            vector::push_back(&mut history.transfers, Transfer {
                nft_id,
                from_address: from_addr,
                to_address,
                timestamp: timestamp::now_seconds(),
                is_gift,
                gift_message: gift_msg
            });
        }

        public entry fun create_trade_offer(
            from: &signer,
            marketplace_addr: address,
            offered_nft_ids: vector<u64>,
            requested_nft_ids: vector<u64>,
            to_address: address,
            message: vector<u8>
        ) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            
            // Verify ownership of offered NFTs
            let i = 0;
            let len = vector::length(&offered_nft_ids);
            while (i < len) {
                let nft_id = *vector::borrow(&offered_nft_ids, i);
                let nft = vector::borrow(&marketplace.nfts, nft_id);
                assert!(nft.owner == signer::address_of(from), ENOT_OWNER);
                i = i + 1;
            };
            
            let trade = TradeOffer {
                id: timestamp::now_seconds(),
                from_address: signer::address_of(from),
                to_address,
                offered_nft_ids,
                requested_nft_ids,
                message,
                status: 0,
                timestamp: timestamp::now_seconds()
            };
            
            move_to(from, trade);
        }

        #[view]
        public fun get_nft_gift_details(
            marketplace_addr: address,
            nft_id: u64
        ): (bool, vector<u8>, address, u64) acquires TransferHistory {
            let history = borrow_global<TransferHistory>(marketplace_addr);
            let len = vector::length(&history.transfers);
            let i = len;
            
            while (i > 0) {
                i = i - 1;
                let transfer = vector::borrow(&history.transfers, i);
                if (transfer.nft_id == nft_id) {
                    if (option::is_some(&transfer.gift_message)) {
                        let gift_msg = option::borrow(&transfer.gift_message);
                        return (
                            true,
                            gift_msg.message,
                            gift_msg.from,
                            gift_msg.timestamp
                        )
                    }
                }
            };
            
            (false, vector::empty(), @0x0, 0)
        }

        #[view]
        public fun is_nft_gift(
            marketplace_addr: address,
            nft_id: u64
        ): bool acquires TransferHistory {
            let history = borrow_global<TransferHistory>(marketplace_addr);
            let len = vector::length(&history.transfers);
            let i = len;
            
            while (i > 0) {
                i = i - 1;
                let transfer = vector::borrow(&history.transfers, i);
                if (transfer.nft_id == nft_id) {
                    return transfer.is_gift
                }
            };
            false
        }

        public entry fun make_offer(
            buyer: &signer,
            marketplace_addr: address,
            nft_id: u64,
            offer_amount: u64,
            expiration_time: u64
        ) acquires MarketplaceData {
            let buyer_addr = signer::address_of(buyer);
            
            // Validate offer amount and buyer funds
            assert!(coin::balance<AptosCoin>(buyer_addr) >= offer_amount, ERROR_INSUFFICIENT_FUNDS);
            
            // Get marketplace data
            let marketplace_data = borrow_global_mut<MarketplaceData>(marketplace_addr);
            
            // Create offer
            let offer = Offer {
                nft_id,
                buyer: buyer_addr,
                amount: offer_amount,
                expiration: expiration_time,
                status: OFFER_STATUS_PENDING
            };
            
            // Transfer coins to escrow
            let offer_coins = coin::withdraw<AptosCoin>(buyer, offer_amount);
            coin::merge(&mut marketplace_data.offer_escrow, offer_coins);
            
            // Store offer
            let offer_id = marketplace_data.next_offer_id;
            marketplace_data.next_offer_id = marketplace_data.next_offer_id + 1;
            table::add(&mut marketplace_data.offers, offer_id, offer);
        }

        public entry fun accept_offer(
            seller: &signer,
            marketplace_addr: address,
            nft_id: u64,
            offer_id: u64
        ) acquires MarketplaceData, Marketplace {
            let seller_addr = signer::address_of(seller);
            let marketplace_data = borrow_global_mut<MarketplaceData>(marketplace_addr);
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);

            // Get and validate NFT ownership
            let nft = vector::borrow_mut(&mut marketplace.nfts, nft_id);
            assert!(nft.owner == seller_addr, ERROR_NOT_OWNER);
            assert!(nft.for_sale, ERROR_NFT_NOT_LISTED);

            // Get and validate offer
            assert!(table::contains(&marketplace_data.offers, offer_id), ERROR_OFFER_NOT_FOUND);
            let offer = table::borrow_mut(&mut marketplace_data.offers, offer_id);
            assert!(offer.status == OFFER_STATUS_PENDING, ERROR_OFFER_NOT_PENDING);
            assert!(timestamp::now_seconds() <= offer.expiration, ERROR_OFFER_EXPIRED);

            // Transfer payment to seller
            let payment = coin::extract(&mut marketplace_data.offer_escrow, offer.amount);
            coin::deposit(seller_addr, payment);

            // Update NFT ownership
            nft.owner = offer.buyer;
            nft.for_sale = false;
            nft.price = 0;

            // Update offer status
            offer.status = OFFER_STATUS_ACCEPTED;

            // Emit event
            event::emit(OfferAccepted {
                nft_id,
                offer_id,
                buyer: offer.buyer,
                seller: seller_addr,
                amount: offer.amount
            });
        }

        public entry fun cancel_offer(
            buyer: &signer,
            marketplace_addr: address,
            offer_id: u64
        ) acquires MarketplaceData {
            let buyer_addr = signer::address_of(buyer);
            let marketplace_data = borrow_global_mut<MarketplaceData>(marketplace_addr);
            
            assert!(table::contains(&marketplace_data.offers, offer_id), ERROR_OFFER_NOT_FOUND);
            let offer = table::borrow_mut(&mut marketplace_data.offers, offer_id);
            assert!(offer.buyer == buyer_addr, ERROR_NOT_OWNER);
            assert!(offer.status == OFFER_STATUS_PENDING, ERROR_OFFER_NOT_PENDING);
            
            // Refund the buyer
            let refund = coin::extract(&mut marketplace_data.offer_escrow, offer.amount);                   coin::deposit(buyer_addr, refund);
            
            // Update offer status
            offer.status = OFFER_STATUS_REJECTED;
            
            // Emit event
            event::emit(OfferCanceled {
                nft_id: offer.nft_id,
                offer_id,
                buyer: buyer_addr
            });
        }

        public entry fun counter_offer(
            seller: &signer,
            marketplace_addr: address,
            nft_id: u64,
            offer_id: u64,
            counter_amount: u64
        ) acquires MarketplaceData {
            let seller_addr = signer::address_of(seller);
            let marketplace_data = borrow_global_mut<MarketplaceData>(marketplace_addr);
            
            // Verify seller owns the NFT
            assert!(table::contains(&marketplace_data.listings, nft_id), ERROR_NFT_NOT_LISTED);
            let listing = table::borrow(&marketplace_data.listings, nft_id);
            assert!(listing.seller == seller_addr, ERROR_NOT_OWNER);
            
            // Get and validate original offer
            assert!(table::contains(&marketplace_data.offers, offer_id), ERROR_OFFER_NOT_FOUND);
            let buyer_addr = table::borrow(&marketplace_data.offers, offer_id).buyer;
            
            // Create counter offer
            let counter_offer_id = marketplace_data.next_offer_id;
            marketplace_data.next_offer_id = marketplace_data.next_offer_id + 1;
            
            // Update original offer status
            let original_offer = table::borrow_mut(&mut marketplace_data.offers, offer_id);
            original_offer.status = OFFER_STATUS_COUNTERED;
            
            // Add counter offer
            table::add(&mut marketplace_data.offers, counter_offer_id, Offer {
                nft_id,
                buyer: buyer_addr,
                amount: counter_amount,
                expiration: timestamp::now_seconds() + COUNTER_OFFER_DURATION,
                status: OFFER_STATUS_COUNTER
            });
            
            // Emit event
            event::emit(CounterOfferCreated {
                nft_id,
                original_offer_id: offer_id,
                counter_offer_id,
                buyer: buyer_addr,
                seller: seller_addr,
                amount: counter_amount
            });
        }

        fun add_offer(
            marketplace_addr: address,
            _nft_id: u64,
            offer: Offer,
            offer_coins: Coin<AptosCoin>
        ) acquires MarketplaceData {
            let marketplace_data = borrow_global_mut<MarketplaceData>(marketplace_addr);
            let offer_id = marketplace_data.next_offer_id;
            marketplace_data.next_offer_id = marketplace_data.next_offer_id + 1;
            
            coin::merge(&mut marketplace_data.offer_escrow, offer_coins);
            table::add(&mut marketplace_data.offers, offer_id, offer);
        }

        #[view]
        public fun get_offer_details(
            marketplace_addr: address,
            offer_id: u64
        ): (u64, address, u64, u64, u8) acquires MarketplaceData {
            let marketplace_data = borrow_global<MarketplaceData>(marketplace_addr);
            let offer = table::borrow(&marketplace_data.offers, offer_id);
            
            (
                offer.nft_id,
                offer.buyer,
                offer.amount,
                offer.expiration,
                offer.status
            )
        }

        #[view]
        public fun get_offers_for_nft(
            marketplace_addr: address,
            nft_id: u64
        ): vector<u64> acquires MarketplaceData {
            let marketplace_data = borrow_global<MarketplaceData>(marketplace_addr);
            let offer_ids = vector::empty<u64>();
            let i = 0;
            
            while (i < marketplace_data.next_offer_id) {
                if (table::contains(&marketplace_data.offers, i)) {
                    let offer = table::borrow(&marketplace_data.offers, i);
                    if (offer.nft_id == nft_id && offer.status == OFFER_STATUS_PENDING) {
                        vector::push_back(&mut offer_ids, i);
                    };
                };
                i = i + 1;
            };
            
            offer_ids
        }

    }
}