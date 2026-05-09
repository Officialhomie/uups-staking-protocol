# UUPS staking protocol (V1 → V2)

Foundry project demonstrating an **ERC-1967 UUPS** upgradeable stake / unstake pool. **V1** holds staked ERC-20 balances; **V2** adds **time-weighted rewards** (`balance × elapsed × rewardMultiplier / 1e18`). Upgrades are gated by **`Ownable2StepUpgradeable`** (`_authorizeUpgrade` is `onlyOwner`).

## Layout

| Contract | Role |
|----------|------|
| [`src/StakingV1.sol`](src/StakingV1.sol) | Initial implementation: `initialize`, `stake`, `unstake`, `uint256[50] __gap`, UUPS + 2-step ownable. |
| [`src/StakingV2.sol`](src/StakingV2.sol) | Adds `rewardMultiplier`, `uint256[49] __gap`, accrual maps, `initializeV2`, `claimRewards`, `syncRewards`. |

Deploy an [`ERC1967Proxy`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/ERC1967/ERC1967Proxy.sol) pointing at `StakingV1` with `initialize(owner, stakingToken)` calldata, then fund the proxy with reward tokens as needed.

## UUPS vs transparent proxy (cost)

- **UUPS:** upgrade entrypoints live in the **implementation**; the proxy stays small. Users pay deployment gas for upgrade logic **once** (in the impl).
- **Transparent:** admin/upgrade logic is split so the proxy is heavier; common pattern for admin-less user contracts.

## Critical UUPS footgun

If you deploy an implementation that **omits** `UUPSUpgradeable` / `_authorizeUpgrade` (or bricks `upgradeToAndCall`), the proxy can become **non-upgradeable** permanently. Always keep **`_authorizeUpgrade` restricted** (here: `onlyOwner`) and verify new implementations expose the correct **`proxiableUUID`**.

## V2 rewards

- `initializeV2(uint256 rewardMultiplier_)` must be run on the proxy after switching the implementation to `StakingV2` (e.g. via `upgradeToAndCall` with encoded init data).
- Users with stake from **V1** should call **`syncRewards()`** once after upgrade so `userLastAccrualTs` is anchored before time elapses (new stakes/unstakes run hooks automatically).

## Commands

```bash
forge build
forge build --sizes
forge test -vvv
forge fmt --check
```

## Dependencies

| Package | Path |
|---------|------|
| forge-std | `lib/forge-std` |
| OpenZeppelin Contracts | `lib/openzeppelin-contracts` |
| OpenZeppelin Contracts Upgradeable | `lib/openzeppelin-contracts-upgradeable` |

Remappings are in [`foundry.toml`](foundry.toml).
