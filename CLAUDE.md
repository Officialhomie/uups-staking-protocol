# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
forge build                   # compile
forge build --sizes           # compile + print contract sizes
forge test -vvv               # run all tests with full traces
forge test --match-test <name> -vvv  # run a single test
forge fmt                     # format source files
forge fmt --check             # check formatting without writing
```

## Architecture

Foundry project (Solidity 0.8.22) implementing an ERC-1967 UUPS upgradeable staking pool, demonstrating a V1 → V2 migration with storage-safe layout.

### Contract hierarchy

```
ERC1967Proxy  →  StakingV1 (initial impl)
                     ↑
                 StakingV2 (upgraded impl, inherits StakingV1)
```

**[src/StakingV1.sol](src/StakingV1.sol)** — Base implementation:
- Inherits `Initializable`, `Ownable2StepUpgradeable`, `UUPSUpgradeable`, `ReentrancyGuardUpgradeable`
- Exposes `stake` / `unstake` with checks-effects-interactions pattern
- Declares `uint256[50] __gap` for future storage slots
- `_authorizeUpgrade` is `onlyOwner`; V2 inherits this restriction
- `_onBalanceChange(address)` is a virtual no-op hook called before and after every balance mutation — V2 overrides it for reward accrual

**[src/StakingV2.sol](src/StakingV2.sol)** — Upgraded implementation:
- Inherits `StakingV1`; adds `rewardMultiplier` (consumes 1 slot from the V1 gap) + `uint256[49] __gap` to keep total layout identical
- Appends `userLastAccrualTs` and `accruedRewards` mappings **after** the gap block (safe append-only pattern)
- Overrides `_onBalanceChange` → calls `_accrue`, which computes `balance × dt × rewardMultiplier / 1e18`
- `initializeV2(uint256)` uses `reinitializer(2)` — call via `upgradeToAndCall` when switching the proxy
- `syncRewards()` anchors `userLastAccrualTs` for users who held V1 stake before upgrade (no automatic anchor without a balance-change event)
- Rewards are paid from the same ERC-20 as the stake token; the contract must be funded beyond the staked principal

### Deployment flow

1. Deploy `StakingV1` implementation
2. Deploy `ERC1967Proxy(address(v1Impl), abi.encodeCall(StakingV1.initialize, (owner, token)))`
3. When upgrading: call `proxy.upgradeToAndCall(address(v2Impl), abi.encodeCall(StakingV2.initializeV2, (multiplier)))`
4. Fund the proxy with reward tokens; existing V1 stakers call `syncRewards()` once

### Storage gap invariant

V1 gap: 50 slots. V2 consumes 1 (`rewardMultiplier`) + keeps 49-slot gap = still 50 total. Any future V3 must follow the same shrink-by-one pattern. Breaking this causes storage collisions.

## Dependencies

| Library | Path | Remapping |
|---------|------|-----------|
| forge-std | `lib/forge-std` | — |
| OpenZeppelin Contracts | `lib/openzeppelin-contracts` | `@openzeppelin/contracts/` |
| OpenZeppelin Contracts Upgradeable | `lib/openzeppelin-contracts-upgradeable` | `@openzeppelin/contracts-upgradeable/` |
