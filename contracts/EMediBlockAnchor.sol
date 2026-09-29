// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  EMediBlockAnchor
 * @notice Batched Merkle anchoring of record commitments. Contribution C3 of
 *         the manuscript and framework functions F2 and F9.
 *
 *         Every Ethereum transaction costs a fixed amount before it does
 *         anything useful, so writing one commitment per record pays that
 *         fixed cost once per record. Here, B record commitments are combined
 *         into a single Merkle root and written together: one transaction and
 *         one storage write for the whole batch, O(1) per batch rather than
 *         O(B). Each individual record can still be proved to belong to the
 *         batch with an inclusion proof of O(log B) hashes, verified by
 *         `verifyInclusion` without any storage write at all.
 *
 *         `anchorSingle` is retained so that the saving can be measured
 *         against it directly; bench/gas_anchor_batch.js reports both.
 *
 *         The commitment written for a clinical record is computed off-chain
 *         over the RFC 8785 canonical form of its HL7 FHIR representation
 *         (contribution C5), so that any other hospital system can recompute
 *         and check it without this software. See offline/src/fhir_convert.py.
 */
contract EMediBlockAnchor {

    // ============================================================
    // State
    // ============================================================

    struct Batch {
        bytes32 root;
        uint32  count;      // number of leaves in the batch
        uint64  anchoredAt;
        address anchoredBy;
    }

    uint256 private _nextBatchId = 1;

    mapping(uint256 => Batch) private _batches;

    /// @dev Single-commitment anchors, kept separate so the two paths can be
    ///      benchmarked against each other on equal terms.
    mapping(bytes32 => uint64) private _singleAnchoredAt;

    // ============================================================
    // Events
    // ============================================================

    event BatchAnchored(
        uint256 indexed batchId,
        bytes32 indexed root,
        uint32  count,
        address indexed anchoredBy,
        uint256 timestamp
    );

    event SingleAnchored(
        bytes32 indexed commitment,
        address indexed anchoredBy,
        uint256 timestamp
    );

    // ============================================================
    // Anchoring
    // ============================================================

    /// @notice Write one record commitment on its own. The unbatched path.
    function anchorSingle(bytes32 commitment) external {
        require(commitment != bytes32(0), "ANCHOR: zero commitment");
        require(_singleAnchoredAt[commitment] == 0, "ANCHOR: already anchored");

        _singleAnchoredAt[commitment] = uint64(block.timestamp);

        emit SingleAnchored(commitment, msg.sender, block.timestamp);
    }

    /// @notice Write the Merkle root of a batch of `count` record commitments.
    /// @dev    Cost is independent of `count`. This is the O(1)-per-batch path.
    function anchorBatch(bytes32 root, uint32 count)
        external
        returns (uint256 batchId)
    {
        require(root != bytes32(0), "ANCHOR: zero root");
        require(count > 0, "ANCHOR: empty batch");

        batchId = _nextBatchId++;

        _batches[batchId] = Batch({
            root:       root,
            count:      count,
            anchoredAt: uint64(block.timestamp),
            anchoredBy: msg.sender
        });

        emit BatchAnchored(batchId, root, count, msg.sender, block.timestamp);
    }

    // ============================================================
    // Verification
    // ============================================================

    /**
     * @notice Verify that `leaf` belongs to the batch identified by `batchId`.
     * @param  proof Sibling hashes from the leaf up to the root.
     * @dev    Pure computation against stored state; no write. Pairs are
     *         hashed in sorted order so that the proof does not need to carry
     *         left/right direction bits. The off-chain tree builder in
     *         offline/src/ uses the same convention.
     */
    function verifyInclusion(
        uint256 batchId,
        bytes32 leaf,
        bytes32[] calldata proof
    )
        external
        view
        returns (bool)
    {
        bytes32 root = _batches[batchId].root;
        if (root == bytes32(0)) {
            return false;
        }
        return _computeRoot(leaf, proof) == root;
    }

    /// @notice Same check against a root supplied directly, for off-chain use.
    function verifyAgainstRoot(
        bytes32 root,
        bytes32 leaf,
        bytes32[] calldata proof
    )
        external
        pure
        returns (bool)
    {
        return _computeRoot(leaf, proof) == root;
    }

    function _computeRoot(bytes32 leaf, bytes32[] calldata proof)
        internal
        pure
        returns (bytes32)
    {
        bytes32 h = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            h = h <= p
                ? keccak256(abi.encodePacked(h, p))
                : keccak256(abi.encodePacked(p, h));
        }

        return h;
    }

    // ============================================================
    // Queries
    // ============================================================

    function batchOf(uint256 batchId)
        external
        view
        returns (bytes32 root, uint32 count, uint64 anchoredAt, address anchoredBy)
    {
        Batch storage b = _batches[batchId];
        return (b.root, b.count, b.anchoredAt, b.anchoredBy);
    }

    function singleAnchoredAt(bytes32 commitment) external view returns (uint64) {
        return _singleAnchoredAt[commitment];
    }

    function batchCount() external view returns (uint256) {
        return _nextBatchId - 1;
    }
}
