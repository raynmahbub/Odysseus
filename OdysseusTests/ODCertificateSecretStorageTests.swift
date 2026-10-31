import CoreData
import Foundation
import XCTest
@testable import Feather

/// Regression coverage for S-03 / ODY-BUG-006: `.p12` passwords belong in the
/// keychain, and deleting a certificate must not silently leave one behind.
@MainActor
final class ODCertificateSecretStorageTests: XCTestCase {
	/// In-memory stand-in for the keychain so the storage logic is testable
	/// without touching the real keychain (or a device).
	final class FakePasswordStore: ODCertificatePasswordStoring {
		var values: [String: String] = [:]
		var failWrites = false
		private(set) var removed: [String] = []

		func password(for uuid: String) -> String? {
			values[uuid]
		}

		func setPassword(_ password: String, for uuid: String) throws {
			if failWrites {
				throw ODCertificatePasswordStoreError.writeFailed
			}
			values[uuid] = password
		}

		func removePassword(for uuid: String) {
			values.removeValue(forKey: uuid)
			removed.append(uuid)
		}
	}

	private var _directory: URL?
	private var _storage: Storage?
	private var _store = FakePasswordStore()

	/// Removes the temporary store. Called from each test rather than
	/// `tearDown()` so the cleanup stays main-actor isolated with the test body.
	private func cleanup() {
		if let storage = _storage {
			for persistentStore in storage.container.persistentStoreCoordinator.persistentStores {
				try? storage.container.persistentStoreCoordinator.remove(persistentStore)
			}
		}
		if let directory = _directory {
			try? FileManager.default.removeItem(at: directory)
		}
		_storage = nil
		_directory = nil
	}

	private func makeStorage() async throws -> Storage {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("OdysseusCertSecretTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		_directory = directory

		let storage = Storage(
			storeURL: directory.appendingPathComponent("Feather.sqlite"),
			passwordStore: _store
		)
		try await storage.waitUntilStoreLoaded()
		_storage = storage
		return storage
	}

	func testAddingCertificateKeepsPasswordOutOfCoreData() async throws {
		let storage = try await makeStorage()
		defer { cleanup() }
		var completionError: Error?

		storage.addCertificate(
			uuid: "cert-1",
			password: "p@ss&word",
			nickname: "Test",
			expiration: Date().addingTimeInterval(86_400),
			playsFeedback: false,
			checksRevocation: false
		) { completionError = $0 }

		XCTAssertNil(completionError)
		let certificates = storage.getAllCertificates()
		let certificate = try XCTUnwrap(certificates.first)

		XCTAssertNil(certificate.password, "the password must not be persisted in Core Data")
		XCTAssertEqual(_store.values["cert-1"], "p@ss&word")
		XCTAssertEqual(storage.password(for: certificate), "p@ss&word")
	}

	func testLegacyPasswordIsMigratedOnRead() async throws {
		let storage = try await makeStorage()
		defer { cleanup() }
		let certificate = CertificatePair(context: storage.context)
		certificate.uuid = "cert-legacy"
		certificate.date = Date()
		certificate.expiration = Date().addingTimeInterval(86_400)
		certificate.password = "legacy-secret"
		try storage.context.save()

		XCTAssertEqual(storage.password(for: certificate), "legacy-secret")
		XCTAssertNil(certificate.password, "the legacy value must be cleared after migration")
		XCTAssertEqual(_store.values["cert-legacy"], "legacy-secret")

		// A second read must come from the keychain and stay correct.
		XCTAssertEqual(storage.password(for: certificate), "legacy-secret")
	}

	func testFailedKeychainWriteDoesNotCreateARecord() async throws {
		let storage = try await makeStorage()
		defer { cleanup() }
		_store.failWrites = true
		var completionError: Error?

		storage.addCertificate(
			uuid: "cert-2",
			password: "secret",
			expiration: Date().addingTimeInterval(86_400),
			playsFeedback: false,
			checksRevocation: false
		) { completionError = $0 }

		XCTAssertNotNil(completionError)
		XCTAssertTrue(storage.getAllCertificates().isEmpty)
	}

	func testDeletingACertificateRemovesItsSecret() async throws {
		let storage = try await makeStorage()
		defer { cleanup() }
		storage.addCertificate(
			uuid: "cert-3",
			password: "secret",
			expiration: Date().addingTimeInterval(86_400),
			playsFeedback: false,
			checksRevocation: false
		) { _ in }

		let certificate = try XCTUnwrap(storage.getAllCertificates().first)
		XCTAssertTrue(storage.deleteCertificate(for: certificate))

		XCTAssertNil(_store.values["cert-3"])
		XCTAssertEqual(_store.removed, ["cert-3"])
		XCTAssertTrue(storage.getAllCertificates().isEmpty)
	}

	func testPasswordWithoutAStoredRecordIsNil() async throws {
		let storage = try await makeStorage()
		defer { cleanup() }
		let certificate = CertificatePair(context: storage.context)
		certificate.uuid = "cert-4"
		certificate.date = Date()
		certificate.expiration = Date().addingTimeInterval(86_400)
		certificate.password = nil
		try storage.context.save()

		XCTAssertNil(storage.password(for: certificate))
		XCTAssertTrue(_store.values.isEmpty)
	}
}
