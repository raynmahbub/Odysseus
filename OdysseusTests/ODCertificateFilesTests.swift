import Foundation
import XCTest
@testable import Feather

/// Coverage for certificate-at-rest handling: the protected location, the
/// path-traversal guard around deletion, and temporary import copies.
final class ODCertificateFilesTests: XCTestCase {
	// MARK: - Location

	func testCertificateStorageIsOutsideTheUserVisibleDocumentsTree() {
		XCTAssertFalse(
			ODCertificateFiles.root.standardizedFileURL.path.hasPrefix(URL.documentsDirectory.standardizedFileURL.path + "/"),
			"certificate material must not sit in the file-sharing directory"
		)
		XCTAssertTrue(ODCertificateFiles.root.path.contains("Application Support"))
	}

	func testLegacyLocationIsStillDocumentsForTheOneTimeMigration() {
		XCTAssertTrue(ODCertificateFiles.legacyRoot.path.hasPrefix(URL.documentsDirectory.path))
		XCTAssertNotEqual(ODCertificateFiles.root, ODCertificateFiles.legacyRoot)
	}

	// MARK: - Names and deletion

	func testSafeNamesRejectTraversalAndSeparators() {
		XCTAssertFalse(ODCertificateFiles.isSafeName(""))
		XCTAssertFalse(ODCertificateFiles.isSafeName("."))
		XCTAssertFalse(ODCertificateFiles.isSafeName(".."))
		XCTAssertFalse(ODCertificateFiles.isSafeName("../Documents"))
		XCTAssertFalse(ODCertificateFiles.isSafeName("a/b"))
		XCTAssertFalse(ODCertificateFiles.isSafeName("a\\b"))
		XCTAssertFalse(ODCertificateFiles.isSafeName(String(repeating: "a", count: 129)))
	}

	func testUUIDNamesAreSafe() {
		XCTAssertTrue(ODCertificateFiles.isSafeName(UUID().uuidString))
	}

	func testDirectoryIsADirectChildOfTheCertificateRoot() throws {
		let url = try ODCertificateFiles.directory(for: UUID().uuidString)

		XCTAssertEqual(
			url.deletingLastPathComponent().standardizedFileURL,
			ODCertificateFiles.root.standardizedFileURL
		)
		XCTAssertTrue(url.path.hasPrefix(ODCertificateFiles.root.path + "/"))
	}

	func testDirectoryRejectsUnsafeNames() {
		XCTAssertThrowsError(try ODCertificateFiles.directory(for: "../Documents")) { error in
			XCTAssertEqual(error as? ODCertificateFilesError, .unsafeName)
		}
	}

	func testRemovalRefusesNamesOutsideTheCertificateRoot() {
		XCTAssertThrowsError(try ODCertificateFiles.removeDirectory(for: "../Documents")) { error in
			XCTAssertEqual(error as? ODCertificateFilesError, .unsafeName)
		}
	}

	func testRemovingAnUnknownCertificateIsReportedAsMissing() throws {
		XCTAssertEqual(try ODCertificateFiles.removeDirectory(for: UUID().uuidString), .missing)
	}

	// MARK: - Protection

	func testProtectAppliesOwnerOnlyPermissionsAndBackupExclusion() throws {
		let directory = ODCertificateFiles.root.appendingPathComponent("test-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let file = directory.appendingPathComponent("cert.p12")
		try Data([0x00, 0x01]).write(to: file)

		ODCertificateFiles.protect(directory: directory)

		let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
		let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)

		XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
		XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

		let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
		XCTAssertEqual(values.isExcludedFromBackup, true)
	}

	// MARK: - Temporary copies

	func testTemporaryCopiesAreRemoved() throws {
		let url = try ODCertificateFiles.writeTemporaryProtected(Data([0x01]), pathExtension: "p12")
		XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

		ODCertificateFiles.removeTemporary(url)
		XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
	}

	func testCleanupNeverDeletesAFileOdysseusDidNotCreate() throws {
		let foreign = FileManager.default.temporaryDirectory
			.appendingPathComponent("user-picked-\(UUID().uuidString).ipa")
		try Data([0x02]).write(to: foreign)
		defer { try? FileManager.default.removeItem(at: foreign) }

		ODCertificateFiles.removeTemporary(foreign)

		XCTAssertTrue(
			FileManager.default.fileExists(atPath: foreign.path),
			"cleanup removed a file it did not create"
		)
	}

	func testCleanupIgnoresDocumentsAndOtherDirectories() throws {
		let document = URL.documentsDirectory.appendingPathComponent("OdysseusImport-\(UUID().uuidString).p12")
		try Data([0x03]).write(to: document)
		defer { try? FileManager.default.removeItem(at: document) }

		ODCertificateFiles.removeTemporary(document)

		XCTAssertTrue(
			FileManager.default.fileExists(atPath: document.path),
			"cleanup must stay inside the temporary directory"
		)
	}
}
