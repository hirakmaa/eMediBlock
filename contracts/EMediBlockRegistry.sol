// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  EMediBlockRegistry
 * @notice Identity and role registry for the eMediBlock framework.
 *         Implements framework function F1 (identity and role registration).
 *
 *         Every other contract in the suite reads roles from here rather than
 *         keeping its own copy. That is the "access restriction" pattern of
 *         Section 2.2, applied once at a single point.
 */
contract EMediBlockRegistry {

    // ============================================================
    // Roles
    // ============================================================

    enum Role {
        None,       // 0 - not registered
        Patient,    // 1
        Doctor,     // 2
        Hospital,   // 3
        Monitor     // 4 - monitoring / IoT ingest service
    }

    address public immutable admin;

    mapping(address => Role) private _roleOf;

    // A doctor is affiliated to a hospital; used by the emergency route so
    // that a counter-signature must come from the same institution.
    mapping(address => address) public affiliationOf;

    // ============================================================
    // Events
    // ============================================================

    event ActorRegistered(
        address indexed actor,
        Role indexed role,
        address indexed affiliation,
        uint256 timestamp
    );

    event ActorDeregistered(
        address indexed actor,
        Role indexed previousRole,
        uint256 timestamp
    );

    // ============================================================
    // Modifiers
    // ============================================================

    modifier onlyAdmin() {
        require(msg.sender == admin, "REG: caller is not admin");
        _;
    }

    // ============================================================
    // Constructor
    // ============================================================

    constructor() {
        admin = msg.sender;
    }

    // ============================================================
    // Registration
    // ============================================================

    /// @notice Register an actor under a role. Admin only.
    /// @dev    `affiliation` is meaningful only for Doctor; pass address(0)
    ///         otherwise. Re-registering an address overwrites its role, which
    ///         is how a role is corrected without deregistering first.
    function register(
        address actor,
        Role role,
        address affiliation
    )
        external
        onlyAdmin
    {
        require(actor != address(0), "REG: zero address");
        require(role != Role.None, "REG: cannot assign None");

        if (role == Role.Doctor) {
            require(affiliation != address(0), "REG: doctor needs affiliation");
            require(_roleOf[affiliation] == Role.Hospital, "REG: affiliation not a hospital");
        }

        _roleOf[actor] = role;
        affiliationOf[actor] = affiliation;

        emit ActorRegistered(actor, role, affiliation, block.timestamp);
    }

    /// @notice Remove an actor's role.
    function deregister(address actor) external onlyAdmin {
        Role previous = _roleOf[actor];
        require(previous != Role.None, "REG: not registered");

        delete _roleOf[actor];
        delete affiliationOf[actor];

        emit ActorDeregistered(actor, previous, block.timestamp);
    }

    // ============================================================
    // Queries
    // ============================================================

    function roleOf(address actor) external view returns (Role) {
        return _roleOf[actor];
    }

    function isPatient(address actor) external view returns (bool) {
        return _roleOf[actor] == Role.Patient;
    }

    function isDoctor(address actor) external view returns (bool) {
        return _roleOf[actor] == Role.Doctor;
    }

    function isHospital(address actor) external view returns (bool) {
        return _roleOf[actor] == Role.Hospital;
    }

    function isMonitor(address actor) external view returns (bool) {
        return _roleOf[actor] == Role.Monitor;
    }
}
