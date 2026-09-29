// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./EMediBlockRegistry.sol";

/**
 * @title  EMediBlockEmergency
 * @notice Accountable break-glass access. Contribution C2 of the manuscript
 *         and framework function F5.
 *
 *         A patient brought in unconscious cannot give consent, so any
 *         consent-based system needs an emergency route. The design principle
 *         here is that disclosure is inseparable from the grant: the same
 *         transaction that opens access writes the record of who opened it.
 *         There is no ordering of operations in which access is obtained and
 *         the disclosure is not written, because they are one state change.
 *
 *         Three further properties, all enforced on-chain:
 *
 *         - Access expires by itself after EXPIRY_WINDOW (24 hours). No action
 *           by anyone is needed to close it.
 *         - Access is void after COUNTERSIGN_WINDOW (2 hours) unless a second,
 *           distinct clinician has countersigned. The first clinician cannot
 *           countersign their own access.
 *         - The route never escalates a role. A caller who is not a registered
 *           doctor cannot open emergency access at all, and a doctor who opens
 *           it gains read access to one patient for a bounded time and nothing
 *           else.
 *
 *         Contrast this with the administrator override that other systems
 *         use, reproduced in test/attacks for comparison: an override grants
 *         unlimited, silent, non-expiring access. Section 4.2 reports the
 *         measured difference.
 *
 *         Pattern applied (Section 2.2): state machine. The admissible
 *         transitions are fixed so that an expired access cannot be
 *         countersigned back into validity.
 */
contract EMediBlockEmergency {

    // ============================================================
    // Wiring and parameters
    // ============================================================

    EMediBlockRegistry public immutable registry;

    uint256 public constant EXPIRY_WINDOW      = 24 hours;
    uint256 public constant COUNTERSIGN_WINDOW = 2 hours;

    // ============================================================
    // State machine
    // ============================================================

    enum Status {
        None,          // 0 - no such access
        Open,          // 1 - opened, awaiting counter-signature
        Countersigned, // 2 - countersigned, valid until openedAt + EXPIRY_WINDOW
        Closed         // 3 - closed early by the opener or the patient
    }

    struct Access {
        address patient;
        address opener;
        address countersigner;
        uint64  openedAt;
        uint64  countersignedAt;
        Status  status;
    }

    uint256 private _nextId = 1;

    mapping(uint256 => Access) private _access;

    // ============================================================
    // Events - the disclosure record
    // ============================================================

    /// @dev Emitted in the SAME transaction that opens access. This is the
    ///      audit record; there is no path to access that skips it.
    event EmergencyOpened(
        uint256 indexed accessId,
        address indexed patient,
        address indexed opener,
        string  reason,
        uint256 openedAt,
        uint256 expiresAt
    );

    event EmergencyCountersigned(
        uint256 indexed accessId,
        address indexed countersigner,
        uint256 timestamp
    );

    event EmergencyClosed(
        uint256 indexed accessId,
        address indexed closedBy,
        uint256 timestamp
    );

    /// @dev Emitted on every read performed under an emergency access, so the
    ///      disclosure record covers use and not merely opening.
    event EmergencyRead(
        uint256 indexed accessId,
        address indexed reader,
        bytes32 indexed recordType,
        uint256 timestamp
    );

    // ============================================================
    // Constructor
    // ============================================================

    constructor(address registryAddress) {
        require(registryAddress != address(0), "EMG: zero registry");
        registry = EMediBlockRegistry(registryAddress);
    }

    // ============================================================
    // Open
    // ============================================================

    /**
     * @notice Open emergency access to `patient`'s records.
     *
     * Preconditions: caller holds the Doctor role; patient is registered as a
     * Patient; reason is non-empty.
     * Effect: creates an Open access and writes the disclosure record naming
     * the caller, the patient, the reason and the time, in this transaction.
     */
    function openEmergency(
        address patient,
        string calldata reason
    )
        external
        returns (uint256 accessId)
    {
        require(registry.isDoctor(msg.sender), "EMG: caller is not a doctor");
        require(registry.isPatient(patient), "EMG: subject is not a patient");
        require(bytes(reason).length > 0, "EMG: reason required");

        accessId = _nextId++;

        _access[accessId] = Access({
            patient:         patient,
            opener:          msg.sender,
            countersigner:   address(0),
            openedAt:        uint64(block.timestamp),
            countersignedAt: 0,
            status:          Status.Open
        });

        emit EmergencyOpened(
            accessId,
            patient,
            msg.sender,
            reason,
            block.timestamp,
            block.timestamp + EXPIRY_WINDOW
        );
    }

    // ============================================================
    // Countersign
    // ============================================================

    /**
     * @notice Countersign an open access.
     *
     * Preconditions: caller holds the Doctor role; caller is not the opener;
     * caller is affiliated to the same hospital as the opener; the access is
     * Open; and the counter-signature window has not elapsed.
     *
     * An access that has passed COUNTERSIGN_WINDOW without a counter-signature
     * is already void, and this function will not revive it — that is the
     * state-machine property.
     */
    function countersign(uint256 accessId) external {
        Access storage a = _access[accessId];

        require(a.status == Status.Open, "EMG: not open");
        require(registry.isDoctor(msg.sender), "EMG: caller is not a doctor");
        require(msg.sender != a.opener, "EMG: cannot countersign own access");
        require(
            registry.affiliationOf(msg.sender) == registry.affiliationOf(a.opener),
            "EMG: different institution"
        );
        require(
            block.timestamp <= uint256(a.openedAt) + COUNTERSIGN_WINDOW,
            "EMG: countersign window elapsed"
        );

        a.countersigner   = msg.sender;
        a.countersignedAt = uint64(block.timestamp);
        a.status          = Status.Countersigned;

        emit EmergencyCountersigned(accessId, msg.sender, block.timestamp);
    }

    // ============================================================
    // Close
    // ============================================================

    /// @notice Close an access early. The opener or the patient may do this.
    function closeEmergency(uint256 accessId) external {
        Access storage a = _access[accessId];

        require(
            a.status == Status.Open || a.status == Status.Countersigned,
            "EMG: not active"
        );
        require(
            msg.sender == a.opener || msg.sender == a.patient,
            "EMG: not opener or patient"
        );

        a.status = Status.Closed;

        emit EmergencyClosed(accessId, msg.sender, block.timestamp);
    }

    // ============================================================
    // Validity
    // ============================================================

    /**
     * @notice Whether an access is valid right now.
     * @dev    The whole policy, in one expression:
     *         - Open, within the counter-signature window  -> valid
     *         - Open, past that window                     -> void
     *         - Countersigned, within 24h of opening       -> valid
     *         - Countersigned, past 24h                    -> expired
     *         - Closed or None                             -> void
     */
    function isActive(uint256 accessId) public view returns (bool) {
        Access storage a = _access[accessId];

        if (a.status == Status.Open) {
            return block.timestamp <= uint256(a.openedAt) + COUNTERSIGN_WINDOW;
        }

        if (a.status == Status.Countersigned) {
            return block.timestamp <= uint256(a.openedAt) + EXPIRY_WINDOW;
        }

        return false;
    }

    /**
     * @notice Record a read performed under an emergency access.
     * @dev    Callers must invoke this rather than merely checking isActive,
     *         so that the disclosure record covers use. It reverts if the
     *         access is not valid, so there is no silent read.
     */
    function recordEmergencyRead(
        uint256 accessId,
        bytes32 recordType
    )
        external
    {
        Access storage a = _access[accessId];

        require(a.status != Status.None, "EMG: no such access");
        require(msg.sender == a.opener, "EMG: not the opener");
        require(isActive(accessId), "EMG: access not valid");

        emit EmergencyRead(accessId, msg.sender, recordType, block.timestamp);
    }

    function accessOf(uint256 accessId)
        external
        view
        returns (
            address patient,
            address opener,
            address countersigner,
            uint64  openedAt,
            uint64  countersignedAt,
            Status  status,
            bool    active
        )
    {
        Access storage a = _access[accessId];
        return (
            a.patient,
            a.opener,
            a.countersigner,
            a.openedAt,
            a.countersignedAt,
            a.status,
            isActive(accessId)
        );
    }
}
