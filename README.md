# Music Royalty Token (MRT)

A fungible ERC-20 token representing fractional ownership of music streaming royalties, built for the IFTE0007 Decentralised Finance and Blockchain module.

## Overview

The Music Royalty Token (MRT) converts music royalty entitlements into programmable digital assets on the Ethereum blockchain. Each token represents a proportional share of all future royalty income deposited by the artist/administrator, enabling retail investors to gain exposure to music royalty cash flows with minimal capital outlay.

## Features

- **Fixed supply ERC-20** — no inflation post-launch; all tokens minted to the deployer at construction
- **Royalty distribution** — owner deposits ETH royalties via `depositRoyalties()`; automatically distributed proportionally to all holders using a reward-per-token accumulator
- **Claim mechanism** — holders call `claimRoyalties()` to withdraw accumulated ETH at any time
- **Redemption window** — owner funds a buyback reserve and opens a redemption window; holders can burn tokens via `redeemTokens()` for a proportional ETH payout
- **Transfer-aware rewards** — the `updateReward` modifier snapshots pending rewards on both sides of every transfer, preventing reward dilution or loss

## Contract

| Property | Value |
|---|---|
| Language | Solidity ^0.8.20 |
| Token Standard | ERC-20 (manual implementation) |
| Token Name | Taylor Swift Royalty-Lover |
| Token Symbol | TST-LVR |
| Network | Sepolia Testnet |
| Contract Address | 0xca26F0e94271b12E736703D970F09d8a54CD2B40 |
| Decimals | 18 |
| Total Supply | 1,000,000 TST-LVR |

## Deployment

The contract was deployed and tested using **Remix IDE** on the **Sepolia testnet**.

### Constructor Parameters

| Parameter | Type | Description |
|---|---|---|
| `_name` | string | Token name (e.g. `"Taylor Swift Royalty-Lover"`) |
| `_symbol` | string | Token symbol (e.g. `"TST-LVR"`) |
| `_songTitle` | string | Human-readable song identifier (e.g. `"Lover"`) |
| `_supply` | uint256 | Total supply in whole tokens (e.g. `1000000`) |

## Key Functions

| Function | Access | Description |
|---|---|---|
| `depositRoyalties()` | Owner | Deposit ETH royalties for distribution |
| `claimRoyalties()` | Holder | Withdraw accumulated royalty earnings |
| `claimableRoyalties(address)` | Public | View pending claimable ETH for an address |
| `redeemTokens(uint256)` | Holder | Burn tokens for a proportional ETH payout from the redemption reserve |
| `fundRedemptionReserve()` | Owner | Fund the buyback reserve with ETH |
| `toggleRedemption(bool)` | Owner | Open or close the redemption window |
| `transferOwnership(address)` | Owner | Transfer contract ownership |
| `contractBalance()` | Public | View total ETH held by the contract |

## Asset–Token–Market–Risk Logic

```
Music Streaming Revenue
        │
        ▼
  Royalty Income (ETH)
        │
        ▼
  depositRoyalties() ──► _rewardPerTokenStored accumulator
        │
        ▼
  Token Holders ◄──────── proportional ETH claim
        │
        ▼
  Secondary Market (DEX / AMM)
        │
        ▼
  Redemption Window (optional buyback)
```

## Risks

- **Regulatory** — MRT may qualify as a security under UK/EU law, requiring FCA authorisation
- **Market** — streaming royalties are variable; returns depend on consumption patterns
- **Oracle** — off-chain royalty data relies on a trusted feed, introducing centralisation risk
- **Smart contract** — bugs in distribution or redemption logic could lock funds
- **Liquidity** — AMM pool depth depends on market participation; lesser-known artists may face wide spreads

## Academic Context

This project was developed as individual coursework for:

> **IFTE0007 – Decentralised Finance and Blockchain**
> Asset Tokenisation Design (60%)
> Submission deadline: 10 April 2026
