// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingV1} from "../src/StakingV1.sol";
import {StakingV2} from "../src/StakingV2.sol";
import {MockERC20} from "./MockERC20.sol";

contract NonUUPS {
    // Deliberately not IERC1822Proxiable — upgrade must fail UUPS check.

    }

contract StakingUUPSTest is Test {
    MockERC20 internal token;
    StakingV1 internal v1Impl;
    StakingV2 internal v2Impl;
    StakingV1 internal staking;
    StakingV2 internal stakingV2;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");

    function setUp() public {
        token = new MockERC20();
        token.mint(alice, 1_000 ether);
        token.mint(owner, 1_000_000 ether);

        v1Impl = new StakingV1();
        bytes memory init = abi.encodeCall(StakingV1.initialize, (owner, address(token)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(v1Impl), init);
        staking = StakingV1(address(proxy));
        stakingV2 = StakingV2(address(proxy));

        v2Impl = new StakingV2();
    }

    function testStakeUnstakeV1() public {
        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        staking.stake(100 ether);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 100 ether);
        assertEq(staking.totalStaked(), 100 ether);

        vm.prank(alice);
        staking.unstake(40 ether);
        assertEq(staking.balanceOf(alice), 60 ether);
    }

    function testUpgradeToV2AndRewards() public {
        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        staking.stake(100 ether);
        vm.stopPrank();

        uint256 mult = 1e15;
        staking.upgradeToAndCall(address(v2Impl), abi.encodeCall(StakingV2.initializeV2, (mult)));

        vm.prank(alice);
        stakingV2.syncRewards();

        vm.warp(block.timestamp + 10);

        uint256 pending = stakingV2.pendingRewards(alice);
        assertGt(pending, 0, "expected time-weighted accrual");

        token.mint(address(staking), 100 ether);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        stakingV2.claimRewards();
        assertGt(token.balanceOf(alice), balBefore);
    }

    function testNonOwnerCannotUpgrade() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.upgradeToAndCall(address(v2Impl), abi.encodeCall(StakingV2.initializeV2, (1 ether)));
    }

    function testOwnable2StepTransferThenUpgrade() public {
        address newOwner = makeAddr("newOwner");

        staking.transferOwnership(newOwner);
        assertEq(staking.pendingOwner(), newOwner);

        vm.prank(newOwner);
        staking.acceptOwnership();
        assertEq(staking.owner(), newOwner);

        vm.prank(newOwner);
        staking.upgradeToAndCall(address(v2Impl), abi.encodeCall(StakingV2.initializeV2, (1 ether)));

        assertEq(stakingV2.rewardMultiplier(), 1 ether);
    }

    function testUpgradeToNonUUPSReverts() public {
        NonUUPS bad = new NonUUPS();

        vm.expectRevert();
        staking.upgradeToAndCall(address(bad), "");
    }

    function testInitializeV2ZeroMultiplierReverts() public {
        StakingV1 v1b = new StakingV1();
        bytes memory init = abi.encodeCall(StakingV1.initialize, (owner, address(token)));
        ERC1967Proxy proxy2 = new ERC1967Proxy(address(v1b), init);
        StakingV1 s2 = StakingV1(address(proxy2));
        StakingV2 v2b = new StakingV2();

        vm.expectRevert(StakingV2.ZeroMultiplier.selector);
        s2.upgradeToAndCall(address(v2b), abi.encodeCall(StakingV2.initializeV2, (uint256(0))));
    }
}
