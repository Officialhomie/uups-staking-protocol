// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakingV1} from "./StakingV1.sol";

/// @title Staking V2 — appends time-weighted rewards (linear in stake × time × multiplier).
/// @dev Storage is append-only after V1: `rewardMultiplier` plus a 49-word gap (V1 kept `uint256[50] __gap`).
contract StakingV2 is StakingV1 {
    using SafeERC20 for IERC20;

    /// @notice Reward rate scale: accrued += balance * dt * rewardMultiplier / 1e18.
    uint256 public rewardMultiplier;

    /// @dev Further expansion slots (tutorial pattern: shrink from 50 to 49 after adding one word above).
    uint256[49] private __gap;

    mapping(address account => uint256) public userLastAccrualTs;
    mapping(address account => uint256) public accruedRewards;

    error ZeroMultiplier();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Run once after upgrading the proxy implementation from V1 to V2.
    function initializeV2(uint256 rewardMultiplier_) external reinitializer(2) {
        if (rewardMultiplier_ == 0) revert ZeroMultiplier();
        rewardMultiplier = rewardMultiplier_;
    }

    function _onBalanceChange(address account) internal override {
        _accrue(account);
    }

    function _accrue(address account) internal {
        uint256 last = userLastAccrualTs[account];
        if (last == 0) {
            userLastAccrualTs[account] = block.timestamp;
            return;
        }
        uint256 bal = balanceOf[account];
        if (bal > 0 && rewardMultiplier > 0) {
            uint256 dt = block.timestamp - last;
            accruedRewards[account] += (bal * dt * rewardMultiplier) / 1e18;
        }
        userLastAccrualTs[account] = block.timestamp;
    }

    /// @notice Claim accrued rewards (same ERC-20 as stake token; fund the contract beyond staked principal).
    /// @notice Anchor reward clock for `msg.sender` (e.g. after V1→V2 upgrade before any stake/unstake).
    function syncRewards() external {
        _accrue(msg.sender);
    }

    function claimRewards() external nonReentrant {
        _accrue(msg.sender);
        uint256 amount = accruedRewards[msg.sender];
        if (amount == 0) {
            return;
        }
        accruedRewards[msg.sender] = 0;
        stakingToken.safeTransfer(msg.sender, amount);
    }

    function pendingRewards(address account) external view returns (uint256 pending) {
        pending = accruedRewards[account];
        uint256 last = userLastAccrualTs[account];
        if (last == 0 || rewardMultiplier == 0) {
            return pending;
        }
        uint256 bal = balanceOf[account];
        if (bal == 0) {
            return pending;
        }
        uint256 dt = block.timestamp - last;
        pending += (bal * dt * rewardMultiplier) / 1e18;
    }
}
