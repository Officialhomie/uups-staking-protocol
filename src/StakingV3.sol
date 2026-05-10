// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {StakingV2} from "./StakingV2.sol";

/// @title Staking V3 — merkle-gated deposits layered over time-weighted rewards.
/// @dev Storage appends one slot (merkleRoot) to V2's section; gap shrinks 49 -> 48.
///      Access control: users must call proveInclusion() with a valid Merkle proof
///      before any stake() call is accepted. The proof is verified against merkleRoot.
///
/// @notice Footgun: rotating merkleRoot mid-window invalidates all existing proofs.
///         Always emit RootUpdated (with timestamp) so off-chain indexers can rebuild
///         the allowlist and notify LPs before the new root goes live.
contract StakingV3 is StakingV2 {
    using MerkleProof for bytes32[];

    /// @notice Merkle root committing the set of whitelisted depositor addresses.
    bytes32 public merkleRoot;

    /// @dev Gap shrinks from V2's 49 to 48 after consuming one slot for merkleRoot.
    uint256[48] private __gap;

    /// @notice Epoch incremented on every root rotation. Whitelisted entries from
    ///         prior epochs are invalidated automatically without per-user storage writes.
    uint256 public whitelistEpoch;

    /// @notice Epoch at which each account last proved inclusion.
    mapping(address account => uint256) public whitelistedAt;

    event RootUpdated(bytes32 oldRoot, bytes32 newRoot, uint256 ts);

    error NotWhitelisted();
    error InvalidProof();
    error ZeroRoot();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Run once after upgrading proxy implementation from V2 to V3.
    /// @param initialRoot Merkle root committing the initial LP allowlist.
    function initializeV3(bytes32 initialRoot) external reinitializer(3) {
        if (initialRoot == bytes32(0)) revert ZeroRoot();
        merkleRoot = initialRoot;
        whitelistEpoch = 1;
    }

    /// @notice Rotate the merkle root. Invalidates all existing whitelist proofs.
    /// @dev Emits RootUpdated with timestamp so indexers can rebuild the allowlist
    ///      off-chain before the next staking window opens.
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        if (newRoot == bytes32(0)) revert ZeroRoot();
        emit RootUpdated(merkleRoot, newRoot, block.timestamp);
        merkleRoot = newRoot;
        unchecked { ++whitelistEpoch; }
    }

    /// @notice Submit a Merkle proof to whitelist msg.sender for the current epoch.
    /// @param proof Sibling hashes from leaf to root (OZ MerkleProof format).
    function proveInclusion(bytes32[] calldata proof) external {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender))));
        if (!proof.verify(merkleRoot, leaf)) revert InvalidProof();
        whitelistedAt[msg.sender] = whitelistEpoch;
    }

    /// @notice Returns true if account has a valid whitelist entry for the current epoch.
    function isWhitelisted(address account) public view returns (bool) {
        return whitelistedAt[account] == whitelistEpoch;
    }

    /// @dev Enforces whitelist before delegating to V2's reward accrual hook.
    ///      Called before and after every balance mutation in stake() / unstake().
    function _onBalanceChange(address account) internal override {
        if (!isWhitelisted(account)) revert NotWhitelisted();
        super._onBalanceChange(account);
    }
}
