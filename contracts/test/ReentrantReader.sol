// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMedicalHealthRecord {
    function readMedicalRecord(bytes32 recordId)
        external
        returns (string memory, bytes32);
}

/**
 * @title  ReentrantReader
 * @notice Attack A1 of the suite. Test-only; never deploy.
 *
 *         Tries to call back into the record contract while an access check is
 *         in progress, in the hope of observing a half-updated state. The
 *         defence is the checks-effects-interactions ordering described in
 *         Section 3.9: the permission test is evaluated and all state written
 *         before control can leave the contract, so there is no window in
 *         which a re-entrant call sees anything different from a fresh one.
 *
 *         `reentryCount` records how many times the callback actually fired.
 *         The test asserts it stays at zero.
 */
contract ReentrantReader {

    IMedicalHealthRecord public immutable target;
    bytes32 public immutable recordId;

    uint256 public reentryCount;
    bool private _inside;

    constructor(address targetAddress, bytes32 recordId_) {
        target = IMedicalHealthRecord(targetAddress);
        recordId = recordId_;
    }

    function attack() external {
        _inside = true;
        target.readMedicalRecord(recordId);
        _inside = false;
    }

    /// @dev Fires if the target ever hands control back to this contract
    ///      mid-call, for example through a value transfer or a callback.
    receive() external payable {
        if (_inside) {
            reentryCount += 1;
            // Try again from inside.
            try target.readMedicalRecord(recordId) returns (string memory, bytes32) {
                // If this ever succeeds, the attack has worked and the test
                // will fail on reentryCount.
            } catch {
                // Expected.
            }
        }
    }

    fallback() external payable {
        if (_inside) {
            reentryCount += 1;
        }
    }
}
