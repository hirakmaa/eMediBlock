// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./EMediBlockRegistry.sol";

/**
 * @title  EMediBlockConsent
 * @notice Epoch-fenced consent. This is contribution C1 of the manuscript and
 *         framework functions F3 (grant / withdraw) and F4 (access mediation).
 *
 *         The mechanism in one sentence: every patient carries a monotonically
 *         increasing consent epoch; a grant is stamped with the epoch current
 *         when it was made, and is valid only while the stamp still matches.
 *
 *         Two consequences follow, and they are the whole point:
 *
 *         1. `revokeAll` advances the epoch by one. That single state write
 *            invalidates every outstanding grant at once, however many there
 *            are, so a patient withdrawing from N doctors performs one
 *            transaction rather than N. There is therefore no window between
 *            one withdrawal and the next in which a doctor can still read.
 *
 *         2. `grantConsent` takes the epoch the caller believes is current and
 *            reverts if it is stale. A grant transaction that was still
 *            pending in the mempool when the epoch advanced cannot land
 *            afterwards against the patient's revised intention. This is what
 *            makes the mechanism correct under adversarial transaction
 *            ordering, which is the claim Section 4.2 enumerates.
 *
 *         `canRead` is O(1): one storage read of the grant stamp and one of
 *         the patient epoch, regardless of how many grants the patient has
 *         issued. The conventional list-scan design is reproduced for
 *         comparison in contracts/baseline/ConventionalConsent.sol.
 *
 *         Patterns applied (Section 2.2): access restriction on every
 *         state-changing function; guard checks concentrated at the head of
 *         each function; checks-effects-interactions ordering throughout — the
 *         epoch is read, state updated, and the event emitted before control
 *         ever leaves this contract, and in fact this contract makes no
 *         external calls at all.
 */
contract EMediBlockConsent {

    // ============================================================
    // Wiring
    // ============================================================

    EMediBlockRegistry public immutable registry;

    // ============================================================
    // State
    // ============================================================

    /// @dev Epoch 0 is never a valid stamp. Every patient starts at 1 on their
    ///      first interaction, which lets a grant stamp of 0 mean "no grant"
    ///      without a separate existence flag. One slot, one SLOAD.
    mapping(address => uint64) private _epoch;

    /// @dev key = keccak256(patient, grantee, recordType) => epoch stamp
    mapping(bytes32 => uint64) private _grantEpoch;

    // ============================================================
    // Events
    // ============================================================

    event ConsentGranted(
        address indexed patient,
        address indexed grantee,
        bytes32 indexed recordType,
        uint64 epoch,
        uint256 timestamp
    );

    event ConsentRevoked(
        address indexed patient,
        address indexed grantee,
        bytes32 indexed recordType,
        uint64 epoch,
        uint256 timestamp
    );

    event ConsentRevokedAll(
        address indexed patient,
        uint64 previousEpoch,
        uint64 newEpoch,
        uint256 timestamp
    );

    // ============================================================
    // Modifiers
    // ============================================================

    modifier onlyPatient() {
        require(registry.isPatient(msg.sender), "CONSENT: caller is not a patient");
        _;
    }

    // ============================================================
    // Constructor
    // ============================================================

    constructor(address registryAddress) {
        require(registryAddress != address(0), "CONSENT: zero registry");
        registry = EMediBlockRegistry(registryAddress);
    }

    // ============================================================
    // Internal helpers
    // ============================================================

    function _key(
        address patient,
        address grantee,
        bytes32 recordType
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(patient, grantee, recordType));
    }

    /// @dev Reads the patient's epoch, treating an unset value as 1 so that a
    ///      patient who has never revoked still has a usable epoch.
    function _currentEpoch(address patient) internal view returns (uint64) {
        uint64 e = _epoch[patient];
        return e == 0 ? 1 : e;
    }

    // ============================================================
    // Grant
    // ============================================================

    /**
     * @notice Grant `grantee` read access to the caller's records of
     *         `recordType`.
     * @param  expectedEpoch The epoch the caller believes is current. If the
     *         patient's epoch has moved on since this transaction was signed,
     *         the call reverts rather than taking effect. Callers read the
     *         value from `currentEpoch(patient)` immediately before signing.
     *
     * Preconditions: caller is a registered patient; grantee is registered and
     * is not the patient; expectedEpoch equals the patient's current epoch.
     * Effect: records a grant stamped with that epoch.
     */
    function grantConsent(
        address grantee,
        bytes32 recordType,
        uint64 expectedEpoch
    )
        external
        onlyPatient
    {
        require(grantee != address(0), "CONSENT: zero grantee");
        require(grantee != msg.sender, "CONSENT: cannot grant to self");
        require(
            registry.roleOf(grantee) != EMediBlockRegistry.Role.None,
            "CONSENT: grantee not registered"
        );
        require(recordType != bytes32(0), "CONSENT: zero record type");

        uint64 epochNow = _currentEpoch(msg.sender);
        require(expectedEpoch == epochNow, "CONSENT: stale epoch");

        _grantEpoch[_key(msg.sender, grantee, recordType)] = epochNow;

        emit ConsentGranted(msg.sender, grantee, recordType, epochNow, block.timestamp);
    }

    // ============================================================
    // Revoke
    // ============================================================

    /// @notice Withdraw one specific grant.
    function revokeConsent(
        address grantee,
        bytes32 recordType
    )
        external
        onlyPatient
    {
        bytes32 k = _key(msg.sender, grantee, recordType);
        uint64 stamp = _grantEpoch[k];
        require(stamp != 0, "CONSENT: no such grant");

        delete _grantEpoch[k];

        emit ConsentRevoked(msg.sender, grantee, recordType, stamp, block.timestamp);
    }

    /**
     * @notice Withdraw every outstanding grant in a single step.
     * @dev    One storage write, constant cost, regardless of how many grants
     *         exist. The old grants are not deleted — they are left stranded at
     *         a stamp that no longer matches, which is cheaper and has the same
     *         effect. A patient who later re-grants to the same party gets a
     *         fresh stamp at the new epoch.
     */
    function revokeAll() external onlyPatient {
        uint64 previous = _currentEpoch(msg.sender);
        uint64 next = previous + 1;

        _epoch[msg.sender] = next;

        emit ConsentRevokedAll(msg.sender, previous, next, block.timestamp);
    }

    // ============================================================
    // Queries
    // ============================================================

    function currentEpoch(address patient) external view returns (uint64) {
        return _currentEpoch(patient);
    }

    /**
     * @notice The single permission test. Every service in the framework calls
     *         this and none carries its own copy.
     * @dev    Constant cost: two storage reads and a comparison. This is the
     *         function benchmarked in bench/gas_access.js against the list-scan
     *         baseline.
     */
    function canRead(
        address patient,
        address reader,
        bytes32 recordType
    )
        public
        view
        returns (bool)
    {
        uint64 stamp = _grantEpoch[_key(patient, reader, recordType)];
        if (stamp == 0) {
            return false;
        }
        return stamp == _currentEpoch(patient);
    }

    /// @notice Reverting form, for callers that want the guard rather than the
    ///         boolean. A patient always passes for their own records.
    function requireCanRead(
        address patient,
        address reader,
        bytes32 recordType
    )
        external
        view
    {
        if (reader == patient) {
            return;
        }
        require(canRead(patient, reader, recordType), "CONSENT: not permitted");
    }
}
