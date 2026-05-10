// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingV1} from "../src/StakingV1.sol";
import {StakingV2} from "../src/StakingV2.sol";
import {StakingV3} from "../src/StakingV3.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Builds a two-leaf Merkle tree: [alice, bob].
///      Leaves use OZ double-hash: keccak256(bytes.concat(keccak256(abi.encode(addr)))).
///      Root = keccak256(abi.encodePacked(leaf0, leaf1)) where leaf0 <= leaf1.
contract StakingV3Test is Test {
    MockERC20 internal token;
    StakingV3 internal staking;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol"); // NOT in tree

    bytes32 internal aliceLeaf;
    bytes32 internal bobLeaf;
    bytes32 internal merkleRoot;

    // Proofs (single sibling each in a 2-leaf tree)
    bytes32[] internal aliceProof;
    bytes32[] internal bobProof;

    function setUp() public {
        // Build leaves
        aliceLeaf = keccak256(bytes.concat(keccak256(abi.encode(alice))));
        bobLeaf   = keccak256(bytes.concat(keccak256(abi.encode(bob))));

        // Sort leaves low -> high so the root is deterministic
        (bytes32 lo, bytes32 hi) = aliceLeaf < bobLeaf
            ? (aliceLeaf, bobLeaf)
            : (bobLeaf, aliceLeaf);
        merkleRoot = keccak256(abi.encodePacked(lo, hi));

        // Each proof is just the sibling leaf. OZ MerkleProof sorts internally.
        aliceProof = new bytes32[](1);
        aliceProof[0] = bobLeaf;

        bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;

        // Deploy: V1 -> V2 -> V3 via upgradeToAndCall chain
        token = new MockERC20();
        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);
        token.mint(owner, 1_000_000 ether);

        StakingV1 v1Impl = new StakingV1();
        bytes memory initV1 = abi.encodeCall(StakingV1.initialize, (owner, address(token)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(v1Impl), initV1);

        StakingV1 s1 = StakingV1(address(proxy));

        StakingV2 v2Impl = new StakingV2();
        s1.upgradeToAndCall(address(v2Impl), abi.encodeCall(StakingV2.initializeV2, (1e15)));

        StakingV3 v3Impl = new StakingV3();
        StakingV2(address(proxy)).upgradeToAndCall(
            address(v3Impl),
            abi.encodeCall(StakingV3.initializeV3, (merkleRoot))
        );

        staking = StakingV3(address(proxy));
    }

    // ------------------------------------------------------------------ happy path

    function testWhitelistedUserCanStake() public {
        vm.prank(alice);
        staking.proveInclusion(aliceProof);
        assertTrue(staking.isWhitelisted(alice));

        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        staking.stake(100 ether);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 100 ether);
    }

    function testWhitelistedUserCanUnstake() public {
        vm.prank(alice);
        staking.proveInclusion(aliceProof);

        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        staking.stake(100 ether);
        staking.unstake(60 ether);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 40 ether);
    }

    function testBothWhitelistedUsersCanStakeIndependently() public {
        vm.prank(alice);
        staking.proveInclusion(aliceProof);

        vm.prank(bob);
        staking.proveInclusion(bobProof);

        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        staking.stake(200 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), type(uint256).max);
        staking.stake(300 ether);
        vm.stopPrank();

        assertEq(staking.totalStaked(), 500 ether);
    }

    // ------------------------------------------------------------------ access control

    function testNonWhitelistedCannotStake() public {
        vm.startPrank(carol);
        token.approve(address(staking), type(uint256).max);
        // carol never called proveInclusion — _onBalanceChange must revert
        vm.expectRevert(StakingV3.NotWhitelisted.selector);
        staking.stake(100 ether);
        vm.stopPrank();
    }

    function testInvalidProofReverts() public {
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(0xdead));

        vm.prank(alice);
        vm.expectRevert(StakingV3.InvalidProof.selector);
        staking.proveInclusion(badProof);
    }

    function testCarolCannotUseAliceProof() public {
        // Alice's proof for alice's leaf won't hash to root for carol's leaf
        vm.prank(carol);
        vm.expectRevert(StakingV3.InvalidProof.selector);
        staking.proveInclusion(aliceProof);
    }

    // ------------------------------------------------------------------ root rotation

    function testRootRotationInvalidatesWhitelist() public {
        vm.prank(alice);
        staking.proveInclusion(aliceProof);
        assertTrue(staking.isWhitelisted(alice));

        // Owner rotates root (new tree, alice no longer included conceptually)
        bytes32 newRoot = keccak256(abi.encodePacked(bytes32(uint256(0xbeef))));
        staking.setMerkleRoot(newRoot);

        // Alice's whitelist entry is now stale (wrong epoch)
        assertFalse(staking.isWhitelisted(alice));

        // Alice cannot stake until she re-proves against new root
        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        vm.expectRevert(StakingV3.NotWhitelisted.selector);
        staking.stake(100 ether);
        vm.stopPrank();
    }

    function testRootRotationEmitsEvent() public {
        bytes32 newRoot = keccak256(abi.encodePacked(bytes32(uint256(0xbeef))));
        vm.expectEmit(true, true, true, true);
        emit StakingV3.RootUpdated(merkleRoot, newRoot, block.timestamp);
        staking.setMerkleRoot(newRoot);
    }

    function testNonOwnerCannotSetMerkleRoot() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.setMerkleRoot(bytes32(uint256(0xdead)));
    }

    function testZeroRootReverts() public {
        vm.expectRevert(StakingV3.ZeroRoot.selector);
        staking.setMerkleRoot(bytes32(0));
    }

    // ------------------------------------------------------------------ reward integration

    function testV3StakerAccruesRewardsFromV2() public {
        vm.prank(alice);
        staking.proveInclusion(aliceProof);

        vm.prank(alice);
        staking.syncRewards(); // anchor clock

        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        staking.stake(100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 pending = staking.pendingRewards(alice);
        assertGt(pending, 0, "whitelisted staker should accrue time-weighted rewards");
    }

    // ------------------------------------------------------------------ upgrade guard

    function testInitializeV3ZeroRootReverts() public {
        StakingV1 v1b = new StakingV1();
        ERC1967Proxy proxy2 = new ERC1967Proxy(
            address(v1b),
            abi.encodeCall(StakingV1.initialize, (owner, address(token)))
        );
        StakingV2 v2b = new StakingV2();
        StakingV1(address(proxy2)).upgradeToAndCall(
            address(v2b),
            abi.encodeCall(StakingV2.initializeV2, (1e15))
        );
        StakingV3 v3b = new StakingV3();
        vm.expectRevert(StakingV3.ZeroRoot.selector);
        StakingV2(address(proxy2)).upgradeToAndCall(
            address(v3b),
            abi.encodeCall(StakingV3.initializeV3, (bytes32(0)))
        );
    }
}
