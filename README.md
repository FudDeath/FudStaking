# FUD Staking Module

This repository contains the `FUD::Staking` Move module for the Sui blockchain. The module implements a staking mechanism for the FUD token, allowing users to stake their tokens, earn rewards based on Annual Percentage Yield (APY), and perform various administrative functions.

## Introduction

The `FUD::Staking` module provides a secure and efficient way for users to stake their FUD tokens on the Sui blockchain. Users can earn rewards over time based on a configurable APY. The module includes functionalities for staking, unstaking, claiming rewards, and administrative controls for managing the staking pool.

## Features

- **Staking**: Users can stake their FUD tokens to participate in the staking pool.
- **Unstaking**: Users can unstake their tokens partially or fully at any time.
- **Rewards**: Users earn rewards based on the amount staked and the duration.
- **Configurable APY**: The APY can be adjusted by the admin after an initial period.
- **Admin Controls**: The admin can fund the pool, withdraw funds, and change the APY.
- **Event Emissions**: The module emits events for staking, unstaking, claiming rewards, and APY changes for transparency.

## Module Overview

### Constants

- `APY_BASIS_POINTS_INITIAL: u64 = 2000;`  
  Initial APY set to 20% (expressed in basis points).

- `BASIS_POINTS_DIVISOR: u64 = 10_000;`  
  Divisor used for basis point calculations.

- `SECONDS_IN_YEAR: u64 = 31_536_000;`  
  Number of seconds in a year, used for reward calculations.

- `INITIAL_APY_DURATION_MS: u64 = 2_592_000_000;`  
  Duration (in milliseconds) for which the initial APY is applicable (30 days).
