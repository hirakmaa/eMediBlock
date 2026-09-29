// SPDX-License-Identifier: MIT
// ============================================================================
// PRESERVED FOR PROVENANCE -- DO NOT DEPLOY
// ============================================================================
// This is the authors' original prototype contract, reproduced verbatim and
// unmodified. It is kept in the repository so that the evolution of the design
// is on the record and so that the claims made in Section 3.9 of the
// manuscript about what changed can be checked against the actual starting
// point rather than against a description of it.
//
// It does NOT implement contributions C1-C6. Specifically it has no access
// control of any kind, no consent mechanism, no emergency-access route, no
// batched anchoring and no recovery. It targets Solidity 0.4.17 and will not
// compile under the 0.8.x toolchain used for everything else here.
//
// The working descendant of this file is ../MedicalHealthRecord.sol.
// ============================================================================

pragma solidity ^0.4.17;

contract MedicalHealthRecord {

    // ============================================================
    // Patient Medical Record
    // JSON string containing patient + medical information
    // ============================================================

    string public medicalRecordJSON;

    // ============================================================
    // Medical File Structure
    // ============================================================

    struct MedicalFile {
        string cid;          // IPFS CID
        bytes32 fileHash;    // File integrity hash
        string fileName;     // File name
        string fileType;     // PDF / JPG / PNG
        uint uploadedAt;     // Blockchain timestamp
        address uploader;    // Uploader wallet address
    }

    // Test Result PDF
    MedicalFile public testResult;

    // Prescription PDF / Image
    MedicalFile public prescription;

    // ============================================================
    // Events
    // ============================================================

    event MedicalRecordCreated(
        address indexed patient,
        uint timestamp
    );

    event MedicalRecordUpdated(
        address indexed patient,
        uint timestamp
    );

    event TestResultUploaded(
        address indexed uploader,
        string cid,
        bytes32 fileHash,
        uint timestamp
    );

    event PrescriptionUploaded(
        address indexed uploader,
        string cid,
        bytes32 fileHash,
        uint timestamp
    );

    // ============================================================
    // Constructor
    // ============================================================

    function MedicalHealthRecord(
        string _medicalRecordJSON
    )
        public
    {
        medicalRecordJSON = _medicalRecordJSON;

        emit MedicalRecordCreated(
            msg.sender,
            now
        );
    }

    // ============================================================
    // Update Medical Record
    // ============================================================

    function updateMedicalRecord(
        string _medicalRecordJSON
    )
        public
    {
        medicalRecordJSON = _medicalRecordJSON;

        emit MedicalRecordUpdated(
            msg.sender,
            now
        );
    }

    // ============================================================
    // Get Medical Record
    // ============================================================

    function getMedicalRecord()
        public
        view
        returns (string)
    {
        return medicalRecordJSON;
    }

    // ============================================================
    // Upload Test Result
    // ============================================================

    function uploadTestResult(
        string _cid,
        bytes32 _fileHash,
        string _fileName,
        string _fileType
    )
        public
    {
        testResult = MedicalFile(
            _cid,
            _fileHash,
            _fileName,
            _fileType,
            now,
            msg.sender
        );

        emit TestResultUploaded(
            msg.sender,
            _cid,
            _fileHash,
            now
        );
    }

    // ============================================================
    // Upload Prescription
    // ============================================================

    function uploadPrescription(
        string _cid,
        bytes32 _fileHash,
        string _fileName,
        string _fileType
    )
        public
    {
        prescription = MedicalFile(
            _cid,
            _fileHash,
            _fileName,
            _fileType,
            now,
            msg.sender
        );

        emit PrescriptionUploaded(
            msg.sender,
            _cid,
            _fileHash,
            now
        );
    }

    // ============================================================
    // Verify Test Result
    // ============================================================

    function verifyTestResult()
        public
        view
        returns (bool)
    {
        return testResult.fileHash != 0;
    }

    // ============================================================
    // Verify Prescription
    // ============================================================

    function verifyPrescription()
        public
        view
        returns (bool)
    {
        return prescription.fileHash != 0;
    }

    // ============================================================
    // Get Test Result
    // ============================================================

    function getTestResult()
        public
        view
        returns (
            string,
            bytes32,
            string,
            string,
            uint,
            address
        )
    {
        return (
            testResult.cid,
            testResult.fileHash,
            testResult.fileName,
            testResult.fileType,
            testResult.uploadedAt,
            testResult.uploader
        );
    }

    // ============================================================
    // Get Prescription
    // ============================================================

    function getPrescription()
        public
        view
        returns (
            string,
            bytes32,
            string,
            string,
            uint,
            address
        )
    {
        return (
            prescription.cid,
            prescription.fileHash,
            prescription.fileName,
            prescription.fileType,
            prescription.uploadedAt,
            prescription.uploader
        );
    }
}
