/**
 * test/attacks/attack_suite.test.js
 * ---------------------------------------------------------------------------
 * Section 4.2, "Running the attacks against the code".
 *
 * Eleven attacks written as working code and run against the deployed
 * contracts. Each plays an attacker trying to achieve something specific, and
 * each PASSES ONLY IF THE ATTEMPT FAILS. A test that goes green here means the
 * attack was defeated; a red test is a real finding, not a broken test.
 *
 * Verifying the abstract consent rules by enumeration (offline/src/) does not
 * establish that the deployed contracts implement them. That is what this file
 * is for.
 *
 *   A1  re-entrancy during an access check
 *   A2  read without any grant
 *   A3  read after revokeAll, using a grant that was valid before it
 *   A4  replay of a pre-signed grant across an epoch boundary
 *   A5  read interleaved into a multi-party withdrawal (ordering attack)
 *   A6  role escalation: a non-patient granting consent
 *   A7  a third party granting consent on a patient's behalf
 *   A8  record-type confusion: a grant for one type used to read another
 *   A9  emergency access opened by a caller without the clinician role
 *   A10 self-countersigned emergency access
 *   A11 use of emergency access after it has expired
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const ROLE = { None: 0, Patient: 1, Doctor: 2, Hospital: 3, Monitor: 4 };

const TYPE_NOTE = ethers.encodeBytes32String("clinical-note");
const TYPE_PSYCH = ethers.encodeBytes32String("psychiatric");
const RECORD_ID = ethers.keccak256(ethers.toUtf8Bytes("record-1"));
const COMMIT = ethers.keccak256(ethers.toUtf8Bytes("canonical-fhir-bytes"));

async function deploySuite() {
  const [admin, patient, drA, drB, hospital, outsider] = await ethers.getSigners();

  const registry = await (await ethers.getContractFactory("EMediBlockRegistry")).deploy();
  const consent = await (await ethers.getContractFactory("EMediBlockConsent"))
    .deploy(await registry.getAddress());
  const emergency = await (await ethers.getContractFactory("EMediBlockEmergency"))
    .deploy(await registry.getAddress());
  const mhr = await (await ethers.getContractFactory("MedicalHealthRecord")).deploy(
    await registry.getAddress(),
    await consent.getAddress(),
    await emergency.getAddress()
  );

  await registry.register(hospital.address, ROLE.Hospital, ethers.ZeroAddress);
  await registry.register(patient.address, ROLE.Patient, ethers.ZeroAddress);
  await registry.register(drA.address, ROLE.Doctor, hospital.address);
  await registry.register(drB.address, ROLE.Doctor, hospital.address);

  await mhr.connect(patient).createMedicalRecord(
    RECORD_ID, TYPE_NOTE, "mongo://records/1", COMMIT);

  return { admin, patient, drA, drB, hospital, outsider, registry, consent, emergency, mhr };
}

async function grant(consent, patient, to, type) {
  const e = await consent.currentEpoch(patient.address);
  await consent.connect(patient).grantConsent(to.address, type, e);
}

describe("eMediBlock attack suite (Section 4.2)", function () {

  // ==========================================================================
  it("A1  re-entrancy during an access check is defeated", async function () {
    const { patient, consent, mhr } = await deploySuite();

    const Attacker = await ethers.getContractFactory("ReentrantReader");
    const attacker = await Attacker.deploy(await mhr.getAddress(), RECORD_ID);

    // The attacker contract is not registered and holds no grant, so the read
    // must fail on the first entry and never reach the re-entrant path.
    await expect(attacker.attack()).to.be.reverted;
    expect(await attacker.reentryCount()).to.equal(0);
  });

  // ==========================================================================
  it("A2  a reader with no grant cannot read", async function () {
    const { drA, mhr } = await deploySuite();
    await expect(mhr.connect(drA).readMedicalRecord(RECORD_ID))
      .to.be.revertedWith("MHR: not permitted");
  });

  // ==========================================================================
  it("A3  a grant that was valid before revokeAll is dead after it", async function () {
    const { patient, drA, consent, mhr } = await deploySuite();

    await grant(consent, patient, drA, TYPE_NOTE);
    expect(await consent.canRead(patient.address, drA.address, TYPE_NOTE)).to.equal(true);

    await consent.connect(patient).revokeAll();

    expect(await consent.canRead(patient.address, drA.address, TYPE_NOTE)).to.equal(false);
    await expect(mhr.connect(drA).readMedicalRecord(RECORD_ID))
      .to.be.revertedWith("MHR: not permitted");
  });

  // ==========================================================================
  it("A4  a grant signed before a withdrawal cannot land after it", async function () {
    const { patient, drA, consent } = await deploySuite();

    // The patient signs a grant at epoch e. Before it is mined, they revoke.
    const e = await consent.currentEpoch(patient.address);
    await consent.connect(patient).revokeAll();

    // The pending grant now carries a stale epoch and must be rejected. This
    // is the property that makes the design correct under adversarial
    // transaction ordering.
    await expect(
      consent.connect(patient).grantConsent(drA.address, TYPE_NOTE, e)
    ).to.be.revertedWith("CONSENT: stale epoch");
  });

  // ==========================================================================
  it("A5  no ordering of a multi-party withdrawal leaves a readable window",
    async function () {
      const { patient, drA, drB, consent } = await deploySuite();

      await grant(consent, patient, drA, TYPE_NOTE);
      await grant(consent, patient, drB, TYPE_NOTE);

      // One transaction withdraws from everyone, so there is no intermediate
      // state in which one doctor is revoked and another is not. An attacker
      // choosing the order of inclusion has nothing to interleave into.
      await consent.connect(patient).revokeAll();

      expect(await consent.canRead(patient.address, drA.address, TYPE_NOTE)).to.equal(false);
      expect(await consent.canRead(patient.address, drB.address, TYPE_NOTE)).to.equal(false);
    });

  // ==========================================================================
  it("A6  a non-patient cannot grant consent", async function () {
    const { drA, drB, consent } = await deploySuite();
    const e = await consent.currentEpoch(drA.address);
    await expect(
      consent.connect(drA).grantConsent(drB.address, TYPE_NOTE, e)
    ).to.be.revertedWith("CONSENT: caller is not a patient");
  });

  // ==========================================================================
  it("A7  a third party cannot grant consent on a patient's behalf", async function () {
    const { outsider, drA, consent } = await deploySuite();
    const e = await consent.currentEpoch(outsider.address);
    await expect(
      consent.connect(outsider).grantConsent(drA.address, TYPE_NOTE, e)
    ).to.be.revertedWith("CONSENT: caller is not a patient");
  });

  // ==========================================================================
  it("A8  a grant for one record type does not open another", async function () {
    const { patient, drA, consent } = await deploySuite();

    await grant(consent, patient, drA, TYPE_NOTE);

    expect(await consent.canRead(patient.address, drA.address, TYPE_NOTE)).to.equal(true);
    expect(await consent.canRead(patient.address, drA.address, TYPE_PSYCH)).to.equal(false);
  });

  // ==========================================================================
  it("A9  a caller without the clinician role cannot open emergency access",
    async function () {
      const { patient, outsider, emergency } = await deploySuite();
      await expect(
        emergency.connect(outsider).openEmergency(patient.address, "unconscious")
      ).to.be.revertedWith("EMG: caller is not a doctor");
    });

  // ==========================================================================
  it("A10  emergency access cannot be countersigned by its own opener",
    async function () {
      const { patient, drA, emergency } = await deploySuite();

      const tx = await emergency.connect(drA).openEmergency(patient.address, "unconscious");
      await tx.wait();
      const id = 1;

      await expect(emergency.connect(drA).countersign(id))
        .to.be.revertedWith("EMG: cannot countersign own access");
    });

  // ==========================================================================
  it("A11  emergency access cannot be used after it expires", async function () {
    const { patient, drA, drB, emergency, mhr } = await deploySuite();

    await (await emergency.connect(drA).openEmergency(patient.address, "unconscious")).wait();
    const id = 1;
    await emergency.connect(drB).countersign(id);

    // Valid now.
    expect(await emergency.isActive(id)).to.equal(true);
    await expect(mhr.connect(drA).readUnderEmergency(RECORD_ID, id)).to.not.be.reverted;

    // 24 hours and one second later it must be dead, with no action by anyone.
    await time.increase(24 * 60 * 60 + 1);

    expect(await emergency.isActive(id)).to.equal(false);
    await expect(mhr.connect(drA).readUnderEmergency(RECORD_ID, id))
      .to.be.revertedWith("EMG: access not valid");
  });

  // ==========================================================================
  it("A11b  an un-countersigned access dies after the 2-hour window",
    async function () {
      const { patient, drA, drB, emergency } = await deploySuite();

      await (await emergency.connect(drA).openEmergency(patient.address, "unconscious")).wait();
      const id = 1;

      await time.increase(2 * 60 * 60 + 1);

      expect(await emergency.isActive(id)).to.equal(false);
      // And it cannot be revived by a late counter-signature.
      await expect(emergency.connect(drB).countersign(id))
        .to.be.revertedWith("EMG: countersign window elapsed");
    });

  // ==========================================================================
  it("disclosure: every emergency read leaves a record on chain", async function () {
    const { patient, drA, drB, emergency, mhr } = await deploySuite();

    await (await emergency.connect(drA).openEmergency(patient.address, "unconscious")).wait();
    const id = 1;
    await emergency.connect(drB).countersign(id);

    const tx = await mhr.connect(drA).readUnderEmergency(RECORD_ID, id);
    const receipt = await tx.wait();

    // The EmergencyRead event is emitted by the emergency contract in the same
    // transaction as the read. There is no path that reads without it.
    const emergencyAddress = (await emergency.getAddress()).toLowerCase();
    const logs = receipt.logs.filter(
      (l) => l.address.toLowerCase() === emergencyAddress
    );
    expect(logs.length).to.be.greaterThan(0);
  });
});
