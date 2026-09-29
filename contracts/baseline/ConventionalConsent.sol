// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  ConventionalConsent
 * @notice A faithful rebuild of the consent design used by the published EHR
 *         systems surveyed in Section 2.1, kept here ONLY as the comparison
 *         baseline for Section 4.3. It is deliberately not improved.
 *
 *         Two properties matter, and both are defects that eMediBlock fixes:
 *
 *         1. Permission checking scans a list, so its cost grows with the
 *            number of parties the patient has granted access to. This is the
 *            O(g) curve in bench/gas_access.js.
 *
 *         2. Withdrawal is per-grantee. A patient withdrawing from several
 *            doctors issues several transactions, and an adversary who
 *            controls the order in which transactions are included can
 *            interleave a read between them. This is the leak that
 *            offline/src/consent_enumerate.py measures.
 *
 *         Do not deploy this contract. It exists to be beaten.
 */
contract ConventionalConsent {

    struct Grant {
        address grantee;
        bytes32 recordType;
        bool active;
    }

    mapping(address => Grant[]) private _grants;

    event ConsentGranted(address indexed patient, address indexed grantee, bytes32 indexed recordType);
    event ConsentRevoked(address indexed patient, address indexed grantee, bytes32 indexed recordType);

    // ============================================================
    // Grant
    // ============================================================

    function grantConsent(address grantee, bytes32 recordType) external {
        Grant[] storage list = _grants[msg.sender];

        // Re-activate an existing entry if there is one, so the list does not
        // grow without bound on repeated grants. Note that this search is
        // itself a scan.
        uint256 n = list.length;
        for (uint256 i = 0; i < n; i++) {
            if (list[i].grantee == grantee && list[i].recordType == recordType) {
                list[i].active = true;
                emit ConsentGranted(msg.sender, grantee, recordType);
                return;
            }
        }

        list.push(Grant({ grantee: grantee, recordType: recordType, active: true }));
        emit ConsentGranted(msg.sender, grantee, recordType);
    }

    // ============================================================
    // Revoke - one grantee at a time, which is the point
    // ============================================================

    function revokeConsent(address grantee, bytes32 recordType) external {
        Grant[] storage list = _grants[msg.sender];
        uint256 n = list.length;

        for (uint256 i = 0; i < n; i++) {
            if (list[i].grantee == grantee && list[i].recordType == recordType) {
                list[i].active = false;
                emit ConsentRevoked(msg.sender, grantee, recordType);
                return;
            }
        }

        revert("BASELINE: no such grant");
    }

    /// @dev Present so that the baseline is not handicapped unfairly: even
    ///      given a bulk withdrawal, the cost is linear in the number of
    ///      grants, against one storage write for the epoch design.
    function revokeAllLinear() external {
        Grant[] storage list = _grants[msg.sender];
        uint256 n = list.length;

        for (uint256 i = 0; i < n; i++) {
            list[i].active = false;
        }
    }

    // ============================================================
    // Permission check - the O(g) scan
    // ============================================================

    function canRead(
        address patient,
        address reader,
        bytes32 recordType
    )
        external
        view
        returns (bool)
    {
        Grant[] storage list = _grants[patient];
        uint256 n = list.length;

        for (uint256 i = 0; i < n; i++) {
            if (
                list[i].active &&
                list[i].grantee == reader &&
                list[i].recordType == recordType
            ) {
                return true;
            }
        }

        return false;
    }

    function grantCount(address patient) external view returns (uint256) {
        return _grants[patient].length;
    }
}
