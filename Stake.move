module FUD::Staking {
    use sui::coin::{self, Coin};
    use sui::event::emit;
    use sui::signer::Signer;
    use sui::clock::Clock;
    use sui::address::Address;

    // Assuming FUD is defined elsewhere with proper coin capabilities
    use FUD::FUD;

    // Constants
    const APY_BASIS_POINTS_INITIAL: u64 = 2000; // 20% APY initially
    const BASIS_POINTS_DIVISOR: u64 = 10_000;
    const SECONDS_IN_YEAR: u64 = 31_536_000;
    const INITIAL_APY_DURATION_MS: u64 = 2_592_000_000; // 30 days in milliseconds

    // Struct to store staking information for each user
    public struct Stake has key, store {
        amount: u64,          // Amount of FUD staked
        stake_time_ms: u64,   // Timestamp when the stake was made (in ms)
        reward_claimed: bool, // Whether the reward has been claimed
    }

    // Struct to represent the staking pool
    public struct StakingPool has key, store {
        total_staked: u64,            // Total FUD staked in the pool
        pool_funds: u64,              // Total funds available for rewards
        apy: u64,                     // Current APY in basis points
        admin: address,               // Admin address
        initial_apy_end_time_ms: u64, // Timestamp when initial APY period ends (in ms)
        // Pool's coin balance represented as a Coin<FUD>
        pool_coin: Coin<FUD>,
    }

    // Events
    public struct StakedEvent has copy, drop, store {
        user: address,
        amount: u64,
    }

    public struct UnstakedEvent has copy, drop, store {
        user: address,
        amount: u64,
    }

    public struct RewardClaimedEvent has copy, drop, store {
        user: address,
        reward: u64,
    }

    public struct APYChangedEvent has copy, drop, store {
        old_apy: u64,
        new_apy: u64,
    }

    // Initialize the staking pool
    public entry fun initialize_pool(
        admin: &signer,
        initial_pool_coin: Coin<FUD>,
        clock: &Clock,
    ) {
        let admin_addr = signer::address_of(admin);
        let current_time_ms = Clock::now_ms(clock);

        // Create the StakingPool resource
        let pool = StakingPool {
            total_staked: 0,
            pool_funds: coin::value(&initial_pool_coin),
            apy: APY_BASIS_POINTS_INITIAL,
            admin: admin_addr,
            initial_apy_end_time_ms: current_time_ms + INITIAL_APY_DURATION_MS,
            pool_coin: initial_pool_coin,
        };

        // Move the pool resource to global storage under admin's address
        move_to(admin, pool);
    }

    // Function to stake FUD tokens
    public entry fun stake_fud(
        staker: &signer,
        coin_to_stake: Coin<FUD>,
        pool_address: address,
        clock: &Clock,
    ) acquires StakingPool, Stake {
        let staker_addr = signer::address_of(staker);
        let current_time_ms = Clock::now_ms(clock);

        // Get the staking pool
        assert!(exists<StakingPool>(pool_address), 1000);
        let pool = borrow_global_mut<StakingPool>(pool_address);

        let amount = coin::value(&coin_to_stake);
        assert!(amount > 0, 1001);

        // Merge staker's coin into pool's coin
        pool.pool_coin = coin::merge(pool.pool_coin, coin_to_stake);

        // Update pool's total staked and pool funds
        pool.total_staked += amount;
        pool.pool_funds += amount;

        // Retrieve or create the user's Stake resource
        if (!exists<Stake>(staker_addr)) {
            let new_stake = Stake {
                amount,
                stake_time_ms: current_time_ms,
                reward_claimed: false,
            };
            move_to(staker, new_stake);
        } else {
            let stake = borrow_global_mut<Stake>(staker_addr);
            stake.amount += amount;
            stake.stake_time_ms = current_time_ms;
        }

        // Emit StakedEvent
        emit(
            StakedEvent {
                user: staker_addr,
                amount,
            }
        );
    }

    // Function to unstake FUD tokens
    public entry fun unstake_fud(
        staker: &signer,
        amount: u64,
        pool_address: address,
    ) acquires StakingPool, Stake {
        let staker_addr = signer::address_of(staker);

        // Get the staking pool
        assert!(exists<StakingPool>(pool_address), 1002);
        let pool = borrow_global_mut<StakingPool>(pool_address);
        assert!(amount > 0, 1003);
        assert!(pool.total_staked >= amount, 1004);

        // Retrieve the user's Stake resource
        assert!(exists<Stake>(staker_addr), 1005);
        let stake = borrow_global_mut<Stake>(staker_addr);
        assert!(stake.amount >= amount, 1006);

        // Update user's stake
        stake.amount -= amount;
        if (stake.amount == 0) {
            move_from<Stake>(staker_addr);
        }

        // Update pool's total staked and pool funds
        pool.total_staked -= amount;
        pool.pool_funds -= amount;

        // Split the required amount from the pool's coin
        let (withdrawn_coin, remaining_pool_coin) = coin::split(pool.pool_coin, amount);
        pool.pool_coin = remaining_pool_coin;

        // Transfer coins back to the staker
        coin::transfer(withdrawn_coin, staker);

        // Emit UnstakedEvent
        emit(
            UnstakedEvent {
                user: staker_addr,
                amount,
            }
        );
    }

    // Function to claim rewards
    public entry fun claim_rewards(
        staker: &signer,
        pool_address: address,
        clock: &Clock,
    ) acquires StakingPool, Stake {
        let staker_addr = signer::address_of(staker);
        let current_time_ms = Clock::now_ms(clock);

        // Get the staking pool
        assert!(exists<StakingPool>(pool_address), 1007);
        let pool = borrow_global_mut<StakingPool>(pool_address);

        // Retrieve the user's Stake resource
        assert!(exists<Stake>(staker_addr), 1008);
        let stake = borrow_global_mut<Stake>(staker_addr);
        assert!(!stake.reward_claimed, 1009);

        // Determine applicable APY based on current time
        let applicable_apy = if current_time_ms >= pool.initial_apy_end_time_ms {
            pool.apy
        } else {
            APY_BASIS_POINTS_INITIAL
        };

        // Calculate staking duration in seconds
        let staking_duration_ms = current_time_ms - stake.stake_time_ms;
        let staking_duration_sec = staking_duration_ms / 1000;

        // Calculate reward
        let reward = (stake.amount * applicable_apy * staking_duration_sec)
            / (BASIS_POINTS_DIVISOR * SECONDS_IN_YEAR);
        assert!(reward > 0, 1010);
        assert!(pool.pool_funds >= reward, 1011);

        // Split reward from pool's coin
        let (reward_coin, remaining_pool_coin) = coin::split(pool.pool_coin, reward);
        pool.pool_coin = remaining_pool_coin;

        // Transfer rewards to the staker
        coin::transfer(reward_coin, staker);

        // Update pool funds
        pool.pool_funds -= reward;

        // Mark reward as claimed
        stake.reward_claimed = true;

        // Emit RewardClaimedEvent
        emit(
            RewardClaimedEvent {
                user: staker_addr,
                reward,
            }
        );
    }

    // Admin function to fund the pool
    public entry fun admin_fund_pool(
        admin: &signer,
        additional_funds: Coin<FUD>,
    ) acquires StakingPool {
        let admin_addr = signer::address_of(admin);

        // Get the staking pool
        assert!(exists<StakingPool>(admin_addr), 2001);
        let pool = borrow_global_mut<StakingPool>(admin_addr);
        assert!(pool.admin == admin_addr, 2002);

        let amount = coin::value(&additional_funds);
        assert!(amount > 0, 2003);

        // Merge additional funds into pool's coin
        pool.pool_coin = coin::merge(pool.pool_coin, additional_funds);

        // Update pool funds
        pool.pool_funds += amount;

        // Optionally emit an event
    }

    // Admin function to withdraw funds from the pool
    public entry fun admin_withdraw_pool(
        admin: &signer,
        amount: u64,
    ) acquires StakingPool {
        let admin_addr = signer::address_of(admin);

        // Get the staking pool
        assert!(exists<StakingPool>(admin_addr), 2004);
        let pool = borrow_global_mut<StakingPool>(admin_addr);
        assert!(pool.admin == admin_addr, 2005);
        assert!(amount > 0, 2006);
        assert!(pool.pool_funds >= amount, 2007);

        // Split amount from pool's coin
        let (withdrawn_coin, remaining_pool_coin) = coin::split(pool.pool_coin, amount);
        pool.pool_coin = remaining_pool_coin;

        // Transfer coins to the admin
        coin::transfer(withdrawn_coin, admin);

        // Update pool funds
        pool.pool_funds -= amount;

        // Optionally emit an event
    }

    // Admin function to change APY
    public entry fun admin_change_apy(
        admin: &signer,
        new_apy: u64,
        clock: &Clock,
    ) acquires StakingPool {
        let admin_addr = signer::address_of(admin);
        let current_time_ms = Clock::now_ms(clock);

        // Get the staking pool
        assert!(exists<StakingPool>(admin_addr), 2008);
        let pool = borrow_global_mut<StakingPool>(admin_addr);
        assert!(pool.admin == admin_addr, 2009);
        assert!(new_apy > 0 && new_apy <= BASIS_POINTS_DIVISOR, 2010);
        assert!(current_time_ms >= pool.initial_apy_end_time_ms, 2011);

        let old_apy = pool.apy;
        pool.apy = new_apy;

        // Emit APYChangedEvent
        emit(
            APYChangedEvent {
                old_apy,
                new_apy,
            }
        );
    }
}
