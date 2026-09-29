// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./EMediBlockRegistry.sol";
import "./EMediBlockConsent.sol";
import "./EMediBlockEmergency.sol";

/**
 * @title  MedicalHealthRecord
 * @notice The record service: storage of the off-chain record pointer and its
 *         integrity commitment, and mediation of every read. Framework
 *         functions F2, F4 and F9.
 *
 *         ------------------------------------------------------------------
 *         PROVENANCE. This contract is the direct descendant of the authors'
 *         original `MedicalHealthRecord` (Solidity 0.4.17). The record model —
 *         a JSON record body plus attached test-result and prescription files,
 *         each with a content identifier, an integrity hash, a name, a type, a
 *         timestamp and an uploader — is carried over unchanged, as are the
 *         event names. What has been added is everything the original lacked:
 *
 *           * Solidity 0.8.x, as stated in Section 3 of the manuscript. The
 *             original used `now`, the pre-0.4.22 constructor form and
 *             unlocated `string` returns, none of which compile after 0.5.
 *           * Access control. In the original, `updateMedicalRecord`,
 *             `uploadTestResult` and `uploadPrescription` were `public` with
 *             no caller check at all, so any address could overwrite any
 *             patient's record. Every state-changing function now checks the
 *             caller's role and their relationship to the patient.
 *           * Consent mediation. Reads go through the single permission test
 *             in EMediBlockConsent, at the patient's current epoch.
 *           * Emergency access. A read that cannot satisfy consent may proceed
 *             under a valid break-glass access, and doing so writes a
 *             disclosure record.
 *           * Many records per patient, rather than one record per deployed
 *             contract instance.
 *           * A real integrity check. The original `verifyTestResult` returned
 *             `fileHash != 0`, which establishes only that something was
 *             uploaded. `verifyFile` now compares a recomputed digest against
 *             the stored commitment.
 *         ------------------------------------------------------------------
 *
 *         Note on storage: the manuscript keeps record bodies in MongoDB and
 *         writes only a commitment on-chain. The `cid` field is retained from
 *         the original design and holds whatever locator the deployment uses —
 *         a MongoDB document id, or an IPFS CID where content addressing is
 *         preferred. The integrity guarantee comes from `fileHash`, not from
 *         the locator.
 */
contract MedicalHealthRecord {

    // ============================================================
    // Wiring
    // ============================================================

    EMediBlockRegistry  public immutable registry;
    EMediBlockConsent   public immutable consent;
    EMediBlockEmergency public immutable emergency;

    // ============================================================
    // Medical File Structure  (carried over from the original)
    // ============================================================

    struct MedicalFile {
        string  cid;         // off-chain locator (MongoDB id or IPFS CID)
        bytes32 fileHash;    // integrity commitment over the file bytes
        string  fileName;    // file name
        string  fileType;    // PDF / JPG / PNG
        uint64  uploadedAt;  // blockchain timestamp
        address uploader;    // uploader wallet address
        bool    exists;
    }

    struct Record {
        address patient;
        bytes32 recordType;
        string  medicalRecordJSON;  // off-chain locator for the record body
        bytes32 recordCommitment;   // over the RFC 8785 canonical FHIR form
        uint64  createdAt;
        uint64  updatedAt;
        bool    exists;
    }

    mapping(bytes32 => Record) private _records;
    mapping(bytes32 => MedicalFile) private _testResult;
    mapping(bytes32 => MedicalFile) private _prescription;

    // ============================================================
    // Events  (names preserved from the original)
    // ============================================================

    event MedicalRecordCreated(
        bytes32 indexed recordId,
        address indexed patient,
        bytes32 indexed recordType,
        bytes32 recordCommitment,
        uint256 timestamp
    );

    event MedicalRecordUpdated(
        bytes32 indexed recordId,
        address indexed patient,
        bytes32 recordCommitment,
        uint256 timestamp
    );

    event TestResultUploaded(
        bytes32 indexed recordId,
        address indexed uploader,
        string  cid,
        bytes32 fileHash,
        uint256 timestamp
    );

    event PrescriptionUploaded(
        bytes32 indexed recordId,
        address indexed uploader,
        string  cid,
        bytes32 fileHash,
        uint256 timestamp
    );

    /// @dev Every mediated read leaves this behind, which is what makes the
    ///      audit trail of Section 3.1 objective six real rather than nominal.
    event RecordRead(
        bytes32 indexed recordId,
        address indexed reader,
        bool    underEmergency,
        uint256 timestamp
    );

    // ============================================================
    // Constructor
    // ============================================================

    constructor(
        address registryAddress,
        address consentAddress,
        address emergencyAddress
    ) {
        require(registryAddress  != address(0), "MHR: zero registry");
        require(consentAddress   != address(0), "MHR: zero consent");
        require(emergencyAddress != address(0), "MHR: zero emergency");

        registry  = EMediBlockRegistry(registryAddress);
        consent   = EMediBlockConsent(consentAddress);
        emergency = EMediBlockEmergency(emergencyAddress);
    }

    // ============================================================
    // Create  (was the original constructor)
    // ============================================================

    function createMedicalRecord(
        bytes32 recordId,
        bytes32 recordType,
        string calldata medicalRecordJSON,
        bytes32 recordCommitment
    )
        external
    {
        require(registry.isPatient(msg.sender), "MHR: caller is not a patient");
        require(!_records[recordId].exists, "MHR: record exists");
        require(recordType != bytes32(0), "MHR: zero record type");
        require(recordCommitment != bytes32(0), "MHR: zero commitment");

        _records[recordId] = Record({
            patient:           msg.sender,
            recordType:        recordType,
            medicalRecordJSON: medicalRecordJSON,
            recordCommitment:  recordCommitment,
            createdAt:         uint64(block.timestamp),
            updatedAt:         uint64(block.timestamp),
            exists:            true
        });

        emit MedicalRecordCreated(
            recordId, msg.sender, recordType, recordCommitment, block.timestamp
        );
    }

    // ============================================================
    // Update
    // ============================================================

    /// @dev The original allowed any caller. Now: the patient, or a doctor the
    ///      patient currently permits for this record type.
    function updateMedicalRecord(
        bytes32 recordId,
        string calldata medicalRecordJSON,
        bytes32 recordCommitment
    )
        external
    {
        Record storage r = _records[recordId];
        require(r.exists, "MHR: no such record");
        require(recordCommitment != bytes32(0), "MHR: zero commitment");
        require(_mayWrite(r, msg.sender), "MHR: not permitted to write");

        r.medicalRecordJSON = medicalRecordJSON;
        r.recordCommitment  = recordCommitment;
        r.updatedAt         = uint64(block.timestamp);

        emit MedicalRecordUpdated(recordId, r.patient, recordCommitment, block.timestamp);
    }

    // ============================================================
    // Read  (mediated)
    // ============================================================

    /**
     * @notice Read a record under ordinary consent.
     * @dev    A `view` function cannot emit, so the audit-writing form is
     *         `readMedicalRecord`; `peekMedicalRecord` is the view form for
     *         callers that only need the permission answer.
     */
    function readMedicalRecord(bytes32 recordId)
        external
        returns (string memory medicalRecordJSON, bytes32 recordCommitment)
    {
        Record storage r = _records[recordId];
        require(r.exists, "MHR: no such record");
        require(
            msg.sender == r.patient ||
            consent.canRead(r.patient, msg.sender, r.recordType),
            "MHR: not permitted"
        );

        emit RecordRead(recordId, msg.sender, false, block.timestamp);
        return (r.medicalRecordJSON, r.recordCommitment);
    }

    /**
     * @notice Read a record under an emergency access.
     * @dev    Calls into the emergency contract, which reverts unless the
     *         access is valid and writes the disclosure record. There is no
     *         path through this function that reads without disclosing.
     */
    function readUnderEmergency(bytes32 recordId, uint256 accessId)
        external
        returns (string memory medicalRecordJSON, bytes32 recordCommitment)
    {
        Record storage r = _records[recordId];
        require(r.exists, "MHR: no such record");

        // Effects and the disclosure are written before anything is returned.
        emergency.recordEmergencyRead(accessId, r.recordType);

        emit RecordRead(recordId, msg.sender, true, block.timestamp);
        return (r.medicalRecordJSON, r.recordCommitment);
    }

    function peekMedicalRecord(bytes32 recordId)
        external
        view
        returns (bool permitted, bytes32 recordCommitment)
    {
        Record storage r = _records[recordId];
        if (!r.exists) {
            return (false, bytes32(0));
        }
        permitted =
            msg.sender == r.patient ||
            consent.canRead(r.patient, msg.sender, r.recordType);
        recordCommitment = r.recordCommitment;
    }

    // ============================================================
    // Attached files
    // ============================================================

    function uploadTestResult(
        bytes32 recordId,
        string calldata cid,
        bytes32 fileHash,
        string calldata fileName,
        string calldata fileType
    )
        external
    {
        Record storage r = _records[recordId];
        require(r.exists, "MHR: no such record");
        require(fileHash != bytes32(0), "MHR: zero file hash");
        require(_mayWrite(r, msg.sender), "MHR: not permitted to write");

        _testResult[recordId] = MedicalFile({
            cid:        cid,
            fileHash:   fileHash,
            fileName:   fileName,
            fileType:   fileType,
            uploadedAt: uint64(block.timestamp),
            uploader:   msg.sender,
            exists:     true
        });

        emit TestResultUploaded(recordId, msg.sender, cid, fileHash, block.timestamp);
    }

    function uploadPrescription(
        bytes32 recordId,
        string calldata cid,
        bytes32 fileHash,
        string calldata fileName,
        string calldata fileType
    )
        external
    {
        Record storage r = _records[recordId];
        require(r.exists, "MHR: no such record");
        require(fileHash != bytes32(0), "MHR: zero file hash");
        require(registry.isDoctor(msg.sender), "MHR: prescriber must be a doctor");
        require(_mayWrite(r, msg.sender), "MHR: not permitted to write");

        _prescription[recordId] = MedicalFile({
            cid:        cid,
            fileHash:   fileHash,
            fileName:   fileName,
            fileType:   fileType,
            uploadedAt: uint64(block.timestamp),
            uploader:   msg.sender,
            exists:     true
        });

        emit PrescriptionUploaded(recordId, msg.sender, cid, fileHash, block.timestamp);
    }

    // ============================================================
    // Integrity verification  (F9)
    // ============================================================

    /**
     * @notice Check a recomputed digest against the stored commitment.
     * @dev    The original returned `fileHash != 0`, which only establishes
     *         that something was uploaded. This compares the actual value, so
     *         a caller who has the off-chain bytes can detect any alteration
     *         from the chain alone.
     */
    function verifyFile(
        bytes32 recordId,
        bool isPrescription,
        bytes32 recomputedHash
    )
        external
        view
        returns (bool)
    {
        MedicalFile storage f = isPrescription
            ? _prescription[recordId]
            : _testResult[recordId];

        if (!f.exists || recomputedHash == bytes32(0)) {
            return false;
        }
        return f.fileHash == recomputedHash;
    }

    function verifyRecord(bytes32 recordId, bytes32 recomputedCommitment)
        external
        view
        returns (bool)
    {
        Record storage r = _records[recordId];
        if (!r.exists || recomputedCommitment == bytes32(0)) {
            return false;
        }
        return r.recordCommitment == recomputedCommitment;
    }

    // ============================================================
    // Getters
    // ============================================================

    function getTestResult(bytes32 recordId)
        external
        view
        returns (string memory, bytes32, string memory, string memory, uint64, address)
    {
        MedicalFile storage f = _testResult[recordId];
        require(f.exists, "MHR: no test result");
        return (f.cid, f.fileHash, f.fileName, f.fileType, f.uploadedAt, f.uploader);
    }

    function getPrescription(bytes32 recordId)
        external
        view
        returns (string memory, bytes32, string memory, string memory, uint64, address)
    {
        MedicalFile storage f = _prescription[recordId];
        require(f.exists, "MHR: no prescription");
        return (f.cid, f.fileHash, f.fileName, f.fileType, f.uploadedAt, f.uploader);
    }

    function recordMeta(bytes32 recordId)
        external
        view
        returns (address patient, bytes32 recordType, uint64 createdAt, uint64 updatedAt)
    {
        Record storage r = _records[recordId];
        require(r.exists, "MHR: no such record");
        return (r.patient, r.recordType, r.createdAt, r.updatedAt);
    }

    // ============================================================
    // Internal
    // ============================================================

    function _mayWrite(Record storage r, address caller) internal view returns (bool) {
        if (caller == r.patient) {
            return true;
        }
        return consent.canRead(r.patient, caller, r.recordType);
    }
}
