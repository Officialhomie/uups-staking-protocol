// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Staking V1 — UUPS implementation with ERC-20 stake / unstake.
contract StakingV1 is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;

    mapping(address account => uint256) public balanceOf;
    uint256 public totalStaked;

    /// @dev Reserved for future layout extensions (see StakingV2).
    uint256[50] private __gap;

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientStake();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address stakingToken_) external initializer {
        if (stakingToken_ == address(0)) revert ZeroAddress();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        stakingToken = IERC20(stakingToken_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _onBalanceChange(msg.sender);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        totalStaked += amount;
        _onBalanceChange(msg.sender);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _onBalanceChange(msg.sender);
        uint256 bal = balanceOf[msg.sender];
        if (bal < amount) revert InsufficientStake();
        unchecked {
            balanceOf[msg.sender] = bal - amount;
            totalStaked -= amount;
        }
        stakingToken.safeTransfer(msg.sender, amount);
        _onBalanceChange(msg.sender);
    }

    /// @dev Hook for V2 reward accrual; no-op in V1.
    function _onBalanceChange(address) internal virtual {}
}
