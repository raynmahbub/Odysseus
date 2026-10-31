import CoreData
import XCTest
@testable import Feather

@MainActor
final class StorageConcurrencyTests: XCTestCase {
	func testConcurrentBackgroundWritesPersistRecordsAndResolveCertificateByUUID() async throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("OdysseusStorageTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let storeURL = directory.appendingPathComponent("Feather.sqlite")

		let storage = Storage(storeURL: storeURL)
		defer {
			for persistentStore in storage.container.persistentStoreCoordinator.persistentStores {
				try? storage.container.persistentStoreCoordinator.remove(persistentStore)
			}
			try? FileManager.default.removeItem(at: directory)
		}
		try await storage.waitUntilStoreLoaded()

		async let firstImportID = storage.addImportedAsync(
			uuid: "import-one",
			appName: "First",
			appIdentifier: "test.first",
			appVersion: "1.0",
			playsFeedback: false
		)
		async let secondImportID = storage.addImportedAsync(
			uuid: "import-two",
			appName: "Second",
			appIdentifier: "test.second",
			appVersion: "2.0",
			playsFeedback: false
		)
		let importedIDs = try await [firstImportID, secondImportID]
		XCTAssertNotEqual(importedIDs[0], importedIDs[1])

		let certificate = CertificatePair(context: storage.context)
		certificate.uuid = "test-certificate"
		certificate.date = Date()
		certificate.expiration = Date().addingTimeInterval(86_400)
		certificate.ppQCheck = false
		certificate.isDefault = false
		try storage.context.save()

		let signedID = try await storage.addSignedAsync(
			uuid: "signed-one",
			certificateUUID: "test-certificate",
			appName: "Signed app",
			appIdentifier: "test.signed",
			appVersion: "3.0",
			playsFeedback: false
		)

		let signedRecord = try XCTUnwrap(try storage.context.existingObject(with: signedID) as? Signed)
		XCTAssertEqual(signedRecord.certificate?.uuid, "test-certificate")
		let viewContext = storage.context
		viewContext.reset()

		let importedNames = try await viewContext.perform {
			let request: NSFetchRequest<Imported> = Imported.fetchRequest()
			request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
			return try viewContext.fetch(request).compactMap(\.name)
		}
		let signedCount = try await viewContext.perform {
			let request: NSFetchRequest<Signed> = Signed.fetchRequest()
			return try viewContext.count(for: request)
		}

		XCTAssertEqual(importedNames, ["First", "Second"])
		XCTAssertEqual(signedCount, 1)

		let signedFiles = directory.appendingPathComponent("Signed", isDirectory: true)
		try FileManager.default.createDirectory(at: signedFiles, withIntermediateDirectories: true)
		try Data("signed app files".utf8).write(to: signedFiles.appendingPathComponent("payload"))
		try await storage.deleteAllRecords(of: Signed.self, filesAt: signedFiles)
		XCTAssertFalse(FileManager.default.fileExists(atPath: signedFiles.path))
		let remainingSignedCount = try await viewContext.perform {
			let request: NSFetchRequest<Signed> = Signed.fetchRequest()
			return try viewContext.count(for: request)
		}
		XCTAssertEqual(remainingSignedCount, 0)
	}

	func testFailedStoreLoadPreservesExistingPathAndReportsError() async throws {
		let blocker = FileManager.default.temporaryDirectory
			.appendingPathComponent("OdysseusStoreBlocker-\(UUID().uuidString)")
		let sentinel = Data("preserve this file".utf8)
		try sentinel.write(to: blocker)
		let appDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("OdysseusFailedReset-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
		let appFile = appDirectory.appendingPathComponent("Preserved.app-data")
		try sentinel.write(to: appFile)
		defer {
			try? FileManager.default.removeItem(at: blocker)
			try? FileManager.default.removeItem(at: appDirectory)
		}

		let storage = Storage(storeURL: blocker.appendingPathComponent("Feather.sqlite"))
		do {
			try await storage.waitUntilStoreLoaded()
			XCTFail("An invalid store location should fail to load")
		} catch {
			XCTAssertNotNil(storage.storeLoadError)
			XCTAssertFalse(storage.isStoreLoaded)
		}
		do {
			try await storage.deleteAllRecords(of: Imported.self, filesAt: appDirectory)
			XCTFail("A failed store should block the Library reset")
		} catch {
			XCTAssertEqual(try Data(contentsOf: appFile), sentinel)
		}
		XCTAssertEqual(try Data(contentsOf: blocker), sentinel)
	}

	func testNewSigningDefaultsDoNotDeleteImportedApps() {
		XCTAssertFalse(Options.defaultOptions.post_deleteAppAfterSigned)
	}
}
