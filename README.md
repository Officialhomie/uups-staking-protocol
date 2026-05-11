# UUPS Staking Protocol

## What is this, in plain English?

Imagine you put money into a savings account. The bank holds your funds and pays you interest over time. Now imagine that instead of a bank — with its paperwork, opening hours, fees, and the trust you place in a human institution — the entire system runs as code on a public blockchain. No bank. No middleman. No one who can freeze your account or change the rules without your knowledge.

That is what this project is. A **staking pool**: you deposit tokens, they earn rewards over time, and you can withdraw whenever you want. The rules are written in code that anyone can read and verify.

But there is something more important happening here than simple staking. This project solves a problem that quietly breaks most smart contract systems in production.

---

## The Problem This Project Solves

When developers deploy a smart contract to Ethereum or any EVM blockchain, the code is permanent. It cannot be changed. If there is a bug — even a critical one that is draining user funds — there is nothing you can do. The contract is live, immutable, and the damage compounds every block.

This creates a brutal tradeoff: either you deploy something perfect (impossible), or you deploy something upgradeable and introduce a whole new set of risks around who controls the upgrade and whether they can steal your money.

Most projects get this wrong. They either:
- Deploy immutable contracts and discover bugs too late
- Deploy upgradeable contracts but implement upgrades so carelessly that a single mistake makes the contract permanently frozen, locking all user funds forever
- Give upgrade control to a single address with no safeguards, creating a rug-pull risk

This project demonstrates how to do it correctly.

---

## Why You Should Pay Attention

If you are building DeFi protocols, DAOs, token reward systems, or any smart contract that needs to evolve after launch — this is the architecture pattern that major protocols like Aave and Compound use in production.

If you are a non-technical founder or investor evaluating a smart contract project, understanding whether the upgrade mechanism is designed safely is one of the most important due diligence questions you can ask. This codebase teaches you exactly what to look for.

If you are a developer new to Solidity, this is one of the most complete, realistic examples of professional-grade upgradeable contract design available as open-source learning material.

---

## What Gets Built, Step by Step

This project builds three versions of the same staking pool, each upgrading the previous one without ever moving user funds or asking users to do anything.

### Version 1 — The Foundation

The first contract is intentionally simple. Users deposit an ERC-20 token. The contract tracks balances. Users can withdraw anytime. There is no reward logic yet.

But V1 is built with the future in mind. It includes two architectural decisions that make everything else possible:

**Decision 1 — Reserved storage.** V1 sets aside 50 empty storage slots that it does not use. These are placeholders that future versions can claim for new data without corrupting existing balances. Like leaving blank pages at the end of a ledger book for future entries.

**Decision 2 — The extension hook.** V1 calls a function called `_onBalanceChange` every time a deposit or withdrawal happens. In V1, this function does nothing. But it is designed to be overridden by future versions that need to do something at that moment — like calculating rewards. V1 does not know what V2 will need. It just promises to call this hook.

### Version 2 — Rewards Without Migration

V2 adds a time-weighted reward system. The longer you stake, and the more you stake, the more you earn. The formula is simple:

```
reward = your balance × seconds elapsed × reward rate
```

V2 activates this by overriding the empty hook from V1. Now every time a balance changes, V2 snapshots how much reward you earned since your last interaction. It also claims one of V1's reserved storage slots for a new variable (the reward rate), then reserves 49 slots going forward — maintaining the exact same total buffer for future versions.

No existing depositor had to move their tokens. The same contract address. The same balances. Just new logic.

### Version 3 — Permissioned Access

V3 adds Merkle-gated deposits. Only addresses whose wallets are included in a cryptographic allowlist (a Merkle tree committed by the contract owner) can deposit. This is how institutional DeFi pools, private investment vaults, and regulated staking products work.

Users prove they are on the allowlist by submitting a cryptographic proof. The contract verifies it on-chain in a single call. The allowlist can be rotated — when the root changes, old proofs expire automatically without any per-user storage writes. The design is gas-efficient and auditable.

---

## The Safety Guarantee

The upgrade mechanism in this project uses a pattern called **UUPS (Universal Upgradeable Proxy Standard)**. Here is what that means and why it matters:

When you interact with this staking pool, you are interacting with a **proxy contract**. The proxy is just a thin shell — it holds all your money and all the state (who deposited what). It delegates all logic to an **implementation contract** that contains the actual rules.

When the owner upgrades the protocol, they swap which implementation the proxy points to. Your money never moves. The address you interact with never changes. You do not need to do anything.

The critical safety property: if anyone — including the owner — deploys a new implementation that accidentally removes the upgrade function, the proxy becomes **permanently frozen**. Every single upgrade must preserve the ability to upgrade again. This project enforces that check automatically.

The owner is also protected by a two-step ownership transfer: handing control to a new address requires the new address to explicitly accept. This prevents accidentally handing control to a wrong address, a bug that has permanently bricked several major protocols.

---

## What You Learn From This Codebase

| Concept | What it teaches |
|---------|----------------|
| UUPS proxy pattern | How upgradeable contracts work at the storage and bytecode level |
| Storage gap pattern | How to add new state variables across upgrades without corrupting old data |
| Virtual hook pattern | How to design extensibility into V1 so V2 can add behavior without rewriting logic |
| Ownable2Step | How to safely transfer control of a protocol |
| Merkle-gated access | How to manage allowlists on-chain without storing addresses individually |
| Epoch-based invalidation | How to revoke all whitelist proofs in one transaction without per-user writes |
| reinitializer guards | How to safely run upgrade initialization without replaying V1 init |

---

## Technical Reference

### Contract Hierarchy

```
ERC1967Proxy  →  StakingV1 (initial implementation)
                      ↑
                 StakingV2 (adds time-weighted rewards)
                      ↑
                 StakingV3 (adds merkle-gated deposits)
```

### Storage Gap Invariant

Each version reserves exactly 50 total slots in its section. When a new variable is added, the gap shrinks by one. This must be maintained by any future V4+.

```
V1: rewardMultiplier (0 used) + __gap[50]
V2: rewardMultiplier (1 used) + __gap[49]
V3: merkleRoot (1 used)       + __gap[48]
```

### Deployment Flow

```bash
# 1. Deploy V1 implementation + proxy
forge create StakingV1
# Deploy ERC1967Proxy(v1Impl, initialize(owner, token))

# 2. Upgrade to V2
upgradeToAndCall(v2Impl, initializeV2(rewardMultiplier))

# 3. Upgrade to V3
upgradeToAndCall(v3Impl, initializeV3(merkleRoot))
```

After upgrading to V2, existing stakers should call `syncRewards()` once to anchor their reward clock. After upgrading to V3, users must call `proveInclusion(proof)` before staking.

### Commands

```bash
forge build
forge build --sizes
forge test -vvv
forge test --match-contract StakingV3Test -vvv
forge fmt --check
```

### Dependencies

| Package | Path |
|---------|------|
| forge-std | `lib/forge-std` |
| OpenZeppelin Contracts | `lib/openzeppelin-contracts` |
| OpenZeppelin Contracts Upgradeable | `lib/openzeppelin-contracts-upgradeable` |
