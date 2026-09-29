// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../EMediBlockConsent.sol";
import "../baseline/ConventionalConsent.sol";

/**
 * @title  GasProbe
 * @notice Test-only helper. `canRead` is a view function in both designs, so
 *         calling it off-chain costs nothing and reveals nothing about the cost
 *         a service actually pays. This contract wraps each one in a
 *         state-changing function, so the cost shows up in a transaction
 *         receipt and can be measured.
 *
 *         The single storage write is identical in both paths, so it cancels
 *         out of the comparison. It is there only to stop the compiler from
 *         optimising the call away.
 *
 *         Not part of the framework. Not for deployment.
 */
contract GasProbe {

    EMediBlockConsent   public immutable epochConsent;
    ConventionalConsent public immutable listConsent;

    bool public lastAnswer;

    constructor(address epochAddress, address listAddress) {
        epochConsent = EMediBlockConsent(epochAddress);
        listConsent  = ConventionalConsent(listAddress);
    }

    function probeEpoch(
        address patient,
        address reader,
        bytes32 recordType
    )
        external
    {
        lastAnswer = epochConsent.canRead(patient, reader, recordType);
    }

    function probeBaseline(
        address patient,
        address reader,
        bytes32 recordType
    )
        external
    {
        lastAnswer = listConsent.canRead(patient, reader, recordType);
    }
}
