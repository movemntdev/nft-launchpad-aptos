//TODO - Individualize collection creator
//TODO - Add signature verification ( Randomize token id )

module nft_launchpad::main {
    use std::vector;
    use std::signer;
    // use std::option;
    use std::string::{Self, String};

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::object::{Self};
    use aptos_std::simple_map::{Self, SimpleMap};
    // use aptos_std::string_utils;

    use aptos_token_objects::aptos_token::{Self};
    use aptos_token_objects::collection::{Self};

    use nft_launchpad::auid_manager;
    //
    // Constants
    //
    const COLLECTION_CREATOR_SEED: vector<u8> = b"COLLECTION_CREATOR_SEED";
    const TAX_RATE_DENOMINATOR: u64 = 1000;

    //
    // Errors
    //
    const ERROR_SIGNER_NOT_ADMIN: u64 = 0;
    const ERROR_STATE_NOT_INITIALIZED: u64 = 1;
    const ERROR_TOO_MANY_NFTS: u64 = 2;
    const ERROR_INVALID_ADDRESS: u64 = 3;
    const ERROR_INVALID_COLLECTION_NAME: u64 = 4;

    //
    // Events
    //
    struct MintEvent has store, drop {
        owner: address,
        token_address: address,
        collection_name: String,
        nft_name: String,
        nft_uri: String
    }
    //
    // Data structures
    //

    struct CollectionInfo has key, store {
        mint_price: u64,
        json_uri: String,
        earned_coins: Coin<AptosCoin>
    }

    struct State has key {
        admin_address: address,
        trigger_address: address,
        collections: SimpleMap<address, CollectionInfo>,
        platform_tax_rate: u64, // based on 1000
        tax_coins: Coin<AptosCoin>,
        mint_events: EventHandle<MintEvent>,
        collection_signer_cap: SignerCapability
    }

    //
    // Assert functions
    //
    inline fun assert_state_initialized() {
        // Assert that State resource exists at the admin address
        assert!(exists<State>(@nft_launchpad), ERROR_STATE_NOT_INITIALIZED);
    }

    //
    // Entry functions
    //

    // init function
    fun init_module(sender: &signer) {
        let sender_addr = signer::address_of(sender);
        assert!(sender_addr == @nft_launchpad, ERROR_INVALID_ADDRESS);
        
        let (_resource_signer, signer_cap) = account::create_resource_account(sender, COLLECTION_CREATOR_SEED);

        aptos_std::debug::print<address>(&signer::address_of(&_resource_signer));

        move_to<State>(sender, State {
            admin_address: sender_addr,
            trigger_address: sender_addr,
            platform_tax_rate: 1,
            tax_coins: coin::zero<AptosCoin>(),
            collections: simple_map::create<address, CollectionInfo>(),
            mint_events: account::new_event_handle<MintEvent>(sender),
            collection_signer_cap: signer_cap
        });
    }

    public entry fun set_addresses(admin: &signer, new_admin_address: address, trigger_address: address) acquires State {
        let state = borrow_global_mut<State>(@nft_launchpad);
        assert!(state.admin_address == signer::address_of(admin), ERROR_SIGNER_NOT_ADMIN);
        state.admin_address = new_admin_address;
        state.trigger_address = trigger_address;
    }

    public entry fun set_tax_rate(admin: &signer, new_tax_rate: u64) acquires State {
        let state = borrow_global_mut<State>(@nft_launchpad);
        assert!(state.admin_address == signer::address_of(admin), ERROR_SIGNER_NOT_ADMIN);
        state.platform_tax_rate = new_tax_rate;
    }

    public entry fun create_collection(
        trigger: &signer,
        max_supply: u64,
        mint_price: u64,
        description: String,
        name: String,
        uri: String,
        json_uri: String,
    ) acquires State {
        let state = borrow_global_mut<State>(@nft_launchpad);
        assert!(state.trigger_address == signer::address_of(trigger), 1);

        let collection_creator = account::create_signer_with_capability(&state.collection_signer_cap);

        aptos_token::create_collection(
            &collection_creator,
            description,
            max_supply, // max_supply
            name,
            uri,
            false,  // mutable_description
            false,  // mutable_royalty
            false,  // mutable_uri
            false,  // mutable_token_description
            false,  // mutable_token_name
            false,  // mutable_token_properties
            false,  // mutable_token_uri
            false,  // tokens_burnable_by_creator
            true,  // tokens_freezable_by_creator
            1,  // royalty_numerator
            10,  // royalty_denominator
        );

        let collection_address = collection::create_collection_address(&@collection_creator, &name);

        simple_map::add(&mut state.collections, collection_address, CollectionInfo {
          mint_price,
          json_uri,
          earned_coins: coin::zero<AptosCoin>(),
        });
    }

    // mint nft
    public entry fun mint_token(
        minter: &signer,
        collection_name: String,
        nft_name: String,
        nft_uri: String
    ) acquires State {

        let state = borrow_global_mut<State>(@nft_launchpad);
        let collection_address = collection::create_collection_address(&@collection_creator, &collection_name);
        
        assert!(simple_map::contains_key(&state.collections, &collection_address), ERROR_INVALID_COLLECTION_NAME);

        // get collection object
        // let collection_obj = object::address_to_object<Collection>(collection_address);

        // make nft_name from collection_name + #number
        //let current_count = *option::borrow_with_default(&collection::count(collection_obj), &0);
        //let nft_name = collection_name;
        //string::append(&mut nft_name, string_utils::format1(&b" #{}", current_count + 1));

        // make nft_uri
        let collection_info = simple_map::borrow_mut(&mut state.collections, &collection_address);
        //let nft_uri = collection_info.json_uri;
        //string::append(&mut nft_uri, string_utils::format1(&b"/{}", current_count + 1));

        // mint nft
        let collection_creator = account::create_signer_with_capability(&state.collection_signer_cap);

        let auids = auid_manager::create();

        let token_address = mint_nft_internal(
            &collection_creator,
            signer::address_of(minter), 
            collection_name, 
            nft_name,
            nft_uri,
            &mut auids
        );

        auid_manager::destroy(auids);

        // pay mint price
        let tax_amount: u128 = (collection_info.mint_price as u128)
                                  * (state.platform_tax_rate as u128)
                                  / (TAX_RATE_DENOMINATOR as u128);

        let coin = coin::withdraw<AptosCoin>(minter, collection_info.mint_price);
        let tax_coin = coin::extract<AptosCoin>(&mut coin, (tax_amount as u64));
        coin::merge<AptosCoin>(&mut collection_info.earned_coins, coin);
        coin::merge<AptosCoin>(&mut state.tax_coins, tax_coin);

        event::emit_event<MintEvent>(
            &mut state.mint_events,
            MintEvent{
                owner: signer::address_of(minter),
                token_address: token_address,
                collection_name,
                nft_name,
                nft_uri
            }
        );
    }

    // withdraw fees ( admin function )
    public entry fun withdraw_tax(account: &signer) acquires State {
        let state = borrow_global_mut<State>(@nft_launchpad);
        assert!(state.admin_address == signer::address_of(account), ERROR_SIGNER_NOT_ADMIN);

        // withdraw fees
        let amt = coin::value(&state.tax_coins);
        let withdraw_coin = coin::extract<AptosCoin>(&mut state.tax_coins, amt);
        coin::deposit<AptosCoin>(signer::address_of(account), withdraw_coin);
    }

    // withdraw earned coins ( admin function )
    public entry fun withdraw_earning(account: &signer, collection_name: String, receiver: address) acquires State {
        let state = borrow_global_mut<State>(@nft_launchpad);
        assert!(state.admin_address == signer::address_of(account), ERROR_SIGNER_NOT_ADMIN);
        
        // get collection address
        let collection_address = collection::create_collection_address(&@collection_creator, &collection_name);

        // fetch collection info in launchpad
        let collection_info = simple_map::borrow_mut(&mut state.collections, &collection_address);

        // withdraw earnings
        let amt = coin::value(&collection_info.earned_coins);
        let withdraw_coin = coin::extract<AptosCoin>(&mut collection_info.earned_coins, amt);

        // send to receiver - just collection artist
        coin::deposit<AptosCoin>(receiver, withdraw_coin);
    }

    //
    // internal functions
    //

    // mint nft 
    fun mint_nft_internal(
        collection_creator: &signer,
        account: address,
        collection_name: String,
        nft_name: String,
        nft_uri: String,
        auids: &mut auid_manager::AuidManager
    ) : address {
        // let creation_number = account::get_guid_next_creation_num(@collection_creator);
        
        aptos_token::mint(
            collection_creator,
            collection_name,
            string::utf8(b""), // description
            nft_name,
            nft_uri,
            vector::empty<String>(),   // property keys
            vector::empty<String>(),  // property types
            vector::empty<vector<u8>>() // property values
        );

        // just minted token_obj
        let token_address = auid_manager::increment(auids);
        let token_obj = object::address_to_object<aptos_token::AptosToken>(
            token_address
        );

        // transfer to minter
        object::transfer(collection_creator, token_obj, account);

        token_address
    }

    #[test_only]
    use aptos_framework::coin::{MintCapability, BurnCapability};
    
    #[test_only]
    use aptos_framework::aptos_account; 

    #[test_only]
    use aptos_framework::aptos_coin; 

    #[test_only]
    struct AptosCoinCap has key {
        mint_cap: MintCapability<AptosCoin>,
        burn_cap: BurnCapability<AptosCoin>,
    }

    #[test_only]
    fun setup(aptos: &signer, core_resources: &signer, addresses: vector<address>) {
        // init the aptos_coin and give merkly_root the mint ability.
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos);

        aptos_account::create_account(signer::address_of(core_resources));
        let coins = coin::mint<AptosCoin>(
            18446744073709551615,
            &mint_cap,
        );
        coin::deposit<AptosCoin>(signer::address_of(core_resources), coins);

        let i = 0;
        while (i < vector::length(&addresses)) {
            aptos_account::transfer(core_resources, *vector::borrow(&addresses, i), 100000000000);
            i = i + 1;
        };

        // gracefully shutdown
        move_to(core_resources, AptosCoinCap {
            mint_cap,
            burn_cap
        });
    }

    #[test(aptos_framework = @0x1, alice = @0xa11ce, bob = @0xb0b, nft_launchpad=@nft_launchpad, trigger = @0xd1e1)]
    fun e2e_test(aptos_framework: signer, nft_launchpad: signer, alice: signer, bob: signer, trigger: signer) acquires State {

        // setup env and create accounts
        setup(&aptos_framework, &alice, vector[@0xb0b, @0xd1e1, @nft_launchpad]);

        // init module
        init_module(&nft_launchpad);

        // set addresses
        // alice is admin, trigger is action trigger
        set_addresses(&nft_launchpad, signer::address_of(&alice), signer::address_of(&trigger));

        // create collection
        let nft_collection_name = string::utf8(b"azuki collection");
        create_collection(
          &trigger,
          1000, // max supply
          10000000, // 0.1 APT
          string::utf8(b"nft collection description"),
          nft_collection_name,
          string::utf8(b"https://azuki-collection-uri"),
          string::utf8(b"ipfs://azuki-collection-uri"),
        );

        // bob tries minting
        let creation_number = account::get_guid_next_creation_num(@collection_creator);
        mint_token(
          &bob,
          nft_collection_name,
          string::utf8(b"azuki collection # 1"),
          string::utf8(b"ipfs://azuki-collection-uri/1"),
        );

        // check token name
        let token_obj = object::address_to_object<aptos_token::AptosToken>(
            object::create_guid_object_address(@collection_creator, creation_number)
        );
        aptos_std::debug::print<String>(&aptos_token_objects::token::name(token_obj));

        // check state info
        let state_info = borrow_global<State>(@nft_launchpad);
        aptos_std::debug::print<State>(state_info);
    }
}
