// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./EMediBlockRegistry.sol";
import "./EMediBlockConsent.sol";

/**
 * @title  EMediBlockRecovery
 * @notice Consent-gated recovery of erasure-coded records. Contribution C4 of
 *         the manuscript and framework function F8.
 *
 *         Each record is split into N fragments using a Reed-Solomon code such
 *         that any K of them suffice to rebuild it. The fragments live
 *         off-chain on independent servers; what is held here is a commitment
 *         to each fragment, the (K, N) parameters, and the authorisation
 *         policy.
 *
 *         The design point is that recovery is not a back door. Rebuilding a
 *         record requires the patient's CURRENT consent, evaluated through the
 *         same single permission test that governs an ordinary read — so a
 *         party whose access was withdrawn cannot use the recovery path to get
 *         what the consent path now denies them. Every attempt is logged
 *         whether it succeeds or fails, which is why `requestRecovery` emits
 *         before it reverts-checks nothing further.
 */
contract EMediBlockRecovery {

    // ============================================================
    // Wiring
    // ============================================================

    EMediBlockRegistry public immutable registry;
    EMediBlockConsent  public immutable consent;

    // ============================================================
    // State
    // ============================================================

    struct CodedRecord {
        address patient;
        bytes32 recordType;
        bytes32 recordCommitment;  // commitment to the reassembled record
        uint16  k;                 // fragments needed
        uint16  n;                 // fragments written
        uint64  registeredAt;
        bool    exists;
    }

    /// @dev recordId => record metadata
    mapping(bytes32 => CodedRecord) private _records;

    /// @dev recordId => fragment index => commitment to that fragment
    mapping(bytes32 => mapping(uint16 => bytes32)) private _fragment;

    // ============================================================
    // Events
    // ============================================================

    event RecordCoded(
        bytes32 indexed recordId,
        address indexed patient,
        bytes32 indexed recordType,
        uint16  k,
        uint16  n,
        bytes32 recordCommitment,
        uint256 timestamp
    );

    event FragmentRegistered(
        bytes32 indexed recordId,
        uint16  indexed index,
        bytes32 commitment
    );

    /// @dev Emitted for EVERY attempt, permitted or not. An attempt that is
    ///      refused still leaves this record behind.
    event RecoveryAttempted(
        bytes32 indexed recordId,
        address indexed requester,
        bool    permitted,
        uint16  fragmentsOffered,
        string  outcome,
        uint256 timestamp
    );

    // ============================================================
    // Constructor
    // ============================================================

    constructor(address registryAddress, address consentAddress) {
        require(registryAddress != address(0), "REC: zero registry");
        require(consentAddress  != address(0), "REC: zero consent");
        registry = EMediBlockRegistry(registryAddress);
        consent  = EMediBlockConsent(consentAddress);
    }

    // ============================================================
    // Registration of coded records
    // ============================================================

    function registerCodedRecord(
        bytes32 recordId,
        bytes32 recordType,
        bytes32 recordCommitment,
        uint16  k,
        uint16  n
    )
        external
    {
        require(registry.isPatient(msg.sender), "REC: caller is not a patient");
        require(!_records[recordId].exists, "REC: already registered");
        require(k > 0 && n >= k, "REC: bad (k,n)");
        require(recordCommitment != bytes32(0), "REC: zero commitment");

        _records[recordId] = CodedRecord({
            patient:          msg.sender,
            recordType:       recordType,
            recordCommitment: recordCommitment,
            k:                k,
            n:                n,
            registeredAt:     uint64(block.timestamp),
            exists:           true
        });

        emit RecordCoded(
            recordId, msg.sender, recordType, k, n, recordCommitment, block.timestamp
        );
    }

    function registerFragment(
        bytes32 recordId,
        uint16  index,
        bytes32 commitment
    )
        external
    {
        CodedRecord storage r = _records[recordId];
        require(r.exists, "REC: no such record");
        require(msg.sender == r.patient, "REC: not the patient");
        require(index < r.n, "REC: index out of range");
        require(commitment != bytes32(0), "REC: zero commitment");

        _fragment[recordId][index] = commitment;

        emit FragmentRegistered(recordId, index, commitment);
    }

    // ============================================================
    // Recovery
    // ============================================================

    /**
     * @notice Request authorisation to rebuild a record from `fragmentsOffered`
     *         surviving fragments.
     * @return permitted Whether reconstruction is authorised.
     *
     * Two conditions must both hold: the requester must pass the same
     * permission test that governs an ordinary read at the patient's current
     * epoch, and at least K fragments must be available. The attempt is logged
     * either way.
     */
    function requestRecovery(
        bytes32 recordId,
        uint16  fragmentsOffered
    )
        external
        returns (bool permitted)
    {
        CodedRecord storage r = _records[recordId];
        require(r.exists, "REC: no such record");

        bool consented =
            msg.sender == r.patient ||
            consent.canRead(r.patient, msg.sender, r.recordType);

        bool enough = fragmentsOffered >= r.k;

        permitted = consented && enough;

        string memory outcome;
        if (!consented) {
            outcome = "refused: consent not current";
        } else if (!enough) {
            outcome = "refused: insufficient fragments";
        } else {
            outcome = "authorised";
        }

        emit RecoveryAttempted(
            recordId, msg.sender, permitted, fragmentsOffered, outcome, block.timestamp
        );
    }

    // ============================================================
    // Queries
    // ============================================================

    function recordOf(bytes32 recordId)
        external
        view
        returns (
            address patient,
            bytes32 recordType,
            bytes32 recordCommitment,
            uint16  k,
            uint16  n,
            uint64  registeredAt
        )
    {
        CodedRecord storage r = _records[recordId];
        require(r.exists, "REC: no such record");
        return (r.patient, r.recordType, r.recordCommitment, r.k, r.n, r.registeredAt);
    }

    function fragmentCommitment(bytes32 recordId, uint16 index)
        external
        view
        returns (bytes32)
    {
        return _fragment[recordId][index];
    }
}
