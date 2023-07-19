# Baton Launchpad 🏇🏇🏇

Baton Launchpad is an NFT launchpad that integrates financial tooling to help creators and collectors create liquid markets around their NFTs.

## Quick start

Installation

```
foundryup
git clone git@github.com:baton-finance/baton-launchpad.git
cd baton-launchpad
forge install
npm install
```

Testing

```
forge test -vvv --gas-report
```

## Contracts overview

| Contract                                       | LOC | Description                                               |
| ---------------------------------------------- | --- | --------------------------------------------------------- |
| [BatonLaunchpad.sol](./src/BatonLaunchpad.sol) | 44  | Factory contract that creates Nfts                        |
| [Nft.sol](./src/Nft.sol)                       | 340 | Nft contract that contains logic for the core feature set |

## Deployments

| Contract                    | Address                                                                                                                      |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| BatonLaunchpad.sol (goerli) | [0xbA82BA626e36531d014B3D906F61Fe9CAba6e09f](https://goerli.etherscan.io/address/0xbA82BA626e36531d014B3D906F61Fe9CAba6e09f) |
| Nft.sol (goerli)            | [0x15Ad24D60685Ce93cE16601E6BfA42d725DC59cd](https://goerli.etherscan.io/address/0x15Ad24D60685Ce93cE16601E6BfA42d725DC59cd) |

## Contents

- [High-level overview](#high-level-overview)
  - [Refunds](#refunds)
  - [Staggered mints](#staggered-mints)
  - [Locked liquidity](#locked-liquidity)
  - [Yield farming](#yield-farming)
  - [Vesting](#vesting)
- [Technical overview](#technical-overview)
  - [Creation](#creation)
  - [Minting](#minting)
  - [Refunds](#refunds-1)
  - [Vesting](#vesting-1)
  - [Locked liquidity](#locked-liquidity-1)
  - [Yield farming](#yield-farming-1)
  - [Owner withdrawals](#owner-withdrawals)
  - [Locked liquidity migrations](#locked-liquidity-migrations)
  - [Leveraging ERC271A to save gas](#leveraging-erc271a-to-save-gas)
  - [System dependencies](#system-dependencies)

---

## High-level overview

Baton Launchpad offers a suite of features that can be configured and tuned by creators to maximize the fairness and amount of liquidity for their NFT. These features include refunds, staggered mints, locked liquidity, yield farming, and vesting. The following sections will explain how each of these features works. Each of the following features is optional and can be configured by the creator.

### Refunds

Refunds are a core feature of Baton Launchpad. They allow creators to set an end date on a mint; If the mint does not complete by this end date then all minters have the option to burn their minted NFTs and receive a refund. This allows minters to have confidence that they will not be stuck with an NFT with no demand.

### Staggered mints

Staggered mints allow creators to specify a set of categories each with a differing mint price and whitelist. For example, you could have a collection that has three different categories: "Early Bird", "General", and "Late Bird". Each category could have a different mint price and whitelist. Staggered mints all occur at the same time, the only differentiator between them is who is allowed to mint in each category and at what price.

### Locked liquidity

One of the largest problems for new collections is that it's very hard to bootstrap liquidity on the secondary market. Locked liquidity is the solution. It allows a creator to allocate some portion of NFTs to be locked in a liquidity pool on an NFT AMM called [Caviar](https://caviar.sh) after the mint completes. For example, if a mint completes and 500 ETH is raised, 200 NFTs are allocated to a liquidity pool, for 0.1 ETH per NFT. This means that there is now a liquidity pool with 20 ETH and 200 NFTs that people can trade against. The liquidity is locked which guarantees that it will always be there. Gone are the days of illiquid secondary markets. The price and amount of ETH allocated to the liquidity pool can be configured by the creator.

### Yield farming

To further incentivize liquidity on the secondary market, creators can also allocate some portion of NFTs to be distributed to liquidity providers on [Caviar](https://caviar.sh) using [Baton Yield Farming](https://baton.finance/farms). This rewards and encourages holders to provide liquidity on the secondary market. The allocated NFTs are distributed linearly to anyone who adds liquidity into the pool and stakes it. The amount of NFTs that a liquidity provider gets is proportional to the amount of liquidity they provide and the amount of time they stake it for. The amount of NFTs allocated to yield farming can be configured by the creator.

### Vesting

Vesting allows creators to specify a vesting schedule for NFTs that are allocated to the team, investors, or other parties. This allows creators to ensure that NFTs are not dumped on the secondary market immediately after the mint completes. The vesting schedule can be configured by the creator. Vesting will start after the mint completes or when the mint end date has passed.

---

## Technical overview

### Creation

[BatonLaunchpad](./src/BatonLaunchpad.sol) is the entry point contract from which all NFTs should be created. It is a factory contract that creates a new [minimal proxy](https://eips.ethereum.org/EIPS/eip-1167) contract for each new [Nft](./src/Nft.sol). It uses create2 to deploy the contracts which allows a user to specify a salt for a vanity address if they choose.

### Minting

The lifecycle of any Nft starts with minting. None of the other features can be used until the mint completes (fully mints out) or expires (goes past the end date without fully minting out). To mint an NFT a minter must choose the amount that they want to mint, the index of the category they want to mint from, and a proof showing that they are in the category's whitelist merkle root (if applicable). The minter must also pay the mint price in ETH. The mint price is determined by the category that the minter chooses. The NFTs are then minted to the user's wallet using [ERC721A](https://github.com/chiru-labs/ERC721A). If a protocol fee has been set then a fee is taken on each mint and sent to the BatonLaunchpad contract which is controlled by Baton.

### Refunds

If refunds are enabled then, following an unsuccessful mint (did not fully mint out and has gone past the end date), the refund process is activated. This allows any user who minted tokens during the minting phase to burn their NFTs and claim back the ETH that they spent. The amount of ETH that they are entitled to per token is calculated as: `total_eth_spent / total_tokens_minted`. There is no expiration on how long a user has to claim their refund.

### Vesting

If vesting is enabled then, following a successful or expired mint, the vesting process is activated. The vesting rate is calculated as: `total_nfts_allocated_to_vesting / vesting_duration`. The vesting duration is the amount of time that it takes for the vesting to be fully complete. Only the configured vesting receiver can trigger a vest call. At any given point, the vesting receiver can choose to vest an `amount` of NFTs (as long as: `amount < total_vested - total_claimed`). The amount that is vested is calculated as: `vesting_rate * (min(current_time, vesting_end_time) - vesting_start_time)`.

### Locked liquidity

If locked liquidity is enabled, then following a successful mint, the locked liquidity process is activated. Anybody can call the `lockLp` function with a specific amount of NFTs to lock. The amount of NFTs must be less than or equal to the amount of NFTs that are allocated to locked liquidity. The amount of ETH that is allocated to the liquidity pool is calculated as: `amount_of_nfts_to_lock * locked_liquidity_price`. If a liquidity pool for the NFT has not been created yet, then the `lockLp` function will attempt to create one. Following the creation of the pair, the `amount_of_nfts_to_lock` is then minted directly to the pair contract before calling the `pair.nftAdd` function. Normally, the pair would attempt to `safeTransferFrom` the NFTs from the caller, but we have provided an override that will skip the state transition in the `transferFrom` method. This is done as a gas optimization. For a deeper explanation please read the [Leveraging ERC271A to save gas](#leveraging-erc721a-to-save-gas) section.

When the liquidity is added we also skip all slippage checks. This is fine because transfers of the NFT to the pair contract are disabled in the `transferFrom` method until the liquidity has finished locking. This means that the Nft contract is the only one that can deposit liquidity, so frontrunning is not an issue -- mitigating the need for slippage checks.

### Yield farming

If yield farming is enabled, then following a successful mint and the finalization of locking liquidity, the yield farming process is activated. Anybody can call the `seedYieldFarm` function with a specific amount of NFTs to allocate to yield farming. The amount of NFTs must be less than or equal to the amount of NFTs that are allocated to yield farming. The amount of NFTs is then minted directly to the caviar pair contract before calling the `pair.wrap` function which mints 1e18 ERC20 fractional tokens for each NFT. Normally, the pair would attempt to `safeTransferFrom` the NFTs from the caller, but we have provided an override that will skip the state transition in the `transferFrom` method. This is done as a gas optimization. For a deeper explanation please read the [Leveraging ERC271A to save gas](#leveraging-erc721a-to-save-gas) section. Those fractional tokens are then used to seed the yield farm.

### Owner withdrawals

Following the completion of a successful mint, liquidity locking being finalized (if enabled), and yield farm being seeded (if enabled), the owner of the NFT can then withdraw the proceeds from the mint. The amount that the owner will receive is the remaining balance of ETH in the contract.

### Locked liquidity migrations

There is an escape hatch for locked liquidity that allows the LP tokens to be migrated to a different contract. For a migration to be completed, there are two steps. First, the owner of the contract initiates a migration via `initiateLockedLpMigration` and specifies an intended target address. Then, after review from the Baton team, the Baton admin can call `migrateLockedLp` with the target address. This will transfer the LP tokens to the target address. This requires two steps to prevent a malicious owner from migrating the LP tokens to an address that they control. The purpose of this is to allow for liquidity to be migrated to newer versions of pools that may be more capital efficient or have some other improvements.

### Leveraging ERC271A to save gas

[ERC721A](https://github.com/chiru-labs/ERC721A) is a library that amortizes the gas cost when minting a given amount of NFTs. To utilize these optimizations we have tuned the `lockLp` and `seedYieldFarm` functions. These functions may reasonably attempt to transfer thousands of NFTs into a liquidity pool or yield farm. This would normally be prohibitively expensive, but with ERC721A we can amortize the cost of minting the NFTs over the entire batch. This allows us to save a significant amount of gas. To do this, we have had to make a few changes.

First, we override the `transferFrom` function to skip any transfers if the `from` address is the NFT contract, the `to` address is the caviar pair, and the `caller` is the caviar pair. Then, we identify any place where the pair contract would normally call `safeTransferFrom` for each token ID and instead mint those token IDs directly to the pair contract using ERC721As `_mint` function. This ensures that the pair contract still has the correct amount of NFTs while also saving gas.

### System dependencies

Baton Launchpad relies on two external systems. These are [Caviar V1](https://github.com/outdoteth/caviar) and [Baton Yield Farms](https://github.com/baton-finance/baton-contracts). Both protocols have been audited.
