//
//  Storage+Shared.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import CoreData
import Foundation
import OSLog
import NimbleExtensions

// MARK: - Apps (Shared)
extension Storage {
	func getUuidDirectory(for app: AppInfoPresentable) -> URL? {
		guard let uuid = app.uuid else { return nil }
		return app.isSigned
			? FileManager.default.signed(uuid)
			: FileManager.default.unsigned(uuid)
	}

	func getAppDirectory(for app: AppInfoPresentable) -> URL? {
		guard let url = getUuidDirectory(for: app) else { return nil }
		return FileManager.default.getPath(in: url, for: "app")
	}

	/// Delete the record on a private context before removing its files. The
	/// managed object is read only on the viewContext queue to take a snapshot;
	/// only its permanent ID and plain values cross to the background context.
	func deleteApp(for app: AppInfoPresentable) async throws {
		guard
			let uuid = app.uuid,
			let managedObject = app as? NSManagedObject
		else {
			throw StorageRecordError.missingObjectID
		}
		let objectID = managedObject.objectID
		let isSigned = app.isSigned
		try await _deleteRecord(objectID: objectID, uuid: uuid, isSigned: isSigned)
	}

	func deleteImportedAppAsync(objectID: NSManagedObjectID, uuid: String) async throws {
		try await _deleteRecord(objectID: objectID, uuid: uuid, isSigned: false)
	}

	private func _deleteRecord(objectID: NSManagedObjectID, uuid: String, isSigned: Bool) async throws {
		try await waitUntilStoreLoaded()
		let directory = isSigned
			? FileManager.default.signed(uuid)
			: FileManager.default.unsigned(uuid)
		let quarantine = directory.deletingLastPathComponent()
			.appendingPathComponent(".\(uuid).deleting-\(UUID().uuidString)", isDirectory: true)
		let movedToQuarantine = FileManager.default.fileExists(atPath: directory.path)

		if movedToQuarantine {
			try await Task.detached(priority: .utility) {
				try FileManager.default.moveItem(at: directory, to: quarantine)
			}.value
		}

		let context = makeBackgroundContext()
		do {
			try await context.perform {
				let object = try context.existingObject(with: objectID)
				guard (isSigned && object is Signed) || (!isSigned && object is Imported) else {
					throw StorageRecordError.wrongEntity
				}
				context.delete(object)
				try context.save()
			}
		} catch {
			await context.perform {
				context.rollback()
			}
			if movedToQuarantine {
				do {
					try await Task.detached(priority: .utility) {
						try FileManager.default.moveItem(at: quarantine, to: directory)
					}.value
				} catch {
					Logger.misc.error("Could not restore app files after a failed Library deletion (error code \(error._code)).")
					throw StorageRecordError.fileRestoreFailed
				}
			}
			throw error
		}

		if movedToQuarantine {
			do {
				try await Task.detached(priority: .utility) {
					try FileManager.default.removeFileIfNeeded(at: quarantine)
				}.value
			} catch {
				Logger.misc.error("Library record was deleted, but quarantined app files could not be removed (error code \(error._code)).")
				throw StorageRecordError.fileCleanupFailed
			}
		}
	}

	func getCertificate(from app: AppInfoPresentable) -> CertificatePair? {
		if let signed = app as? Signed {
			return signed.certificate
		}
		return nil
	}
}

private enum StorageRecordError: LocalizedError {
	case missingObjectID
	case wrongEntity
	case fileRestoreFailed
	case fileCleanupFailed

	var errorDescription: String? {
		switch self {
		case .missingObjectID: return .localized("The selected app is no longer in the Library.")
		case .wrongEntity: return .localized("The selected Library record has an unexpected type.")
		case .fileRestoreFailed: return .localized("The Library deletion failed and the app files could not be restored; they remain in a hidden recovery directory.")
		case .fileCleanupFailed: return .localized("The Library record was deleted, but its quarantined app files could not be removed.")
		}
	}
}

// MARK: - Helpers
struct AnyApp: Identifiable {
	let base: AppInfoPresentable
	var archive: Bool = false

	var id: String {
		base.uuid ?? UUID().uuidString
	}
}

protocol AppInfoPresentable {
	var name: String? { get }
	var version: String? { get }
	var identifier: String? { get }
	var date: Date? { get }
	var icon: String? { get }
	var uuid: String? { get }
	var isSigned: Bool { get }
}

extension Signed: AppInfoPresentable {
	var isSigned: Bool { true }
}

extension Imported: AppInfoPresentable {
	var isSigned: Bool { false }
}
