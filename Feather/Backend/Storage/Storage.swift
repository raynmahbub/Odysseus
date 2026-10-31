//
//  Persistence.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import Foundation
import OSLog

// All synchronous access to viewContext is main-actor isolated. Detached
// work uses fresh background contexts and passes only object IDs/snapshots.
@MainActor
final class Storage: ObservableObject {
	static let shared = Storage()
	let container: NSPersistentContainer

	private let _name = "Feather"
	private enum StoreLoadState {
		case loading
		case loaded
		case failed(Error)
	}
	private var _storeLoadState: StoreLoadState = .loading
	private var _storeLoadWaiters: [CheckedContinuation<Void, Error>] = []
	@Published private(set) var storeLoadError: Error?
	@Published private(set) var isStoreLoaded = false

	init(inMemory: Bool = false, storeURL: URL? = nil) {
		let model = Self._loadManagedObjectModel()
		container = NSPersistentContainer(
			name: _name,
			managedObjectModel: model ?? NSManagedObjectModel()
		)
		guard model != nil else {
			let error = StorageInitializationError.modelNotFound
			storeLoadError = error
			_storeLoadState = .failed(error)
			Logger.misc.error("Core Data model '\(self._name)' was not found in the app bundle; Library data was not modified.")
			return
		}

		if let description = container.persistentStoreDescriptions.first {
			if inMemory {
				description.type = NSInMemoryStoreType
				description.url = nil
			} else if let storeURL {
				description.url = storeURL
			}
		}

		container.viewContext.automaticallyMergesChangesFromParent = true
		container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		_loadPersistentStore()
	}

	var context: NSManagedObjectContext {
		container.viewContext
	}

	/// Awaitable readiness avoids semaphores, synchronous waits, and races
	/// against NSPersistentContainer.loadPersistentStores().
	func waitUntilStoreLoaded() async throws {
		switch _storeLoadState {
		case .loaded:
			return
		case .failed(let error):
			throw error
		case .loading:
			try await withCheckedThrowingContinuation { continuation in
				_storeLoadWaiters.append(continuation)
			}
		}
	}

	func makeBackgroundContext() -> NSManagedObjectContext {
		let context = container.newBackgroundContext()
		context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		context.undoManager = nil
		return context
	}

	func saveContext() {
		guard context.hasChanges else { return }
		do {
			try context.save()
		} catch {
			Logger.misc.error("Core Data save failed (error code \(error._code)); existing store files were preserved.")
		}
	}

	/// Deletes all records of one entity on a private context. If app files are
	/// supplied, they are quarantined first and restored if the database save
	/// fails, so a failed reset cannot silently erase the corresponding files.
	func deleteAllRecords<T: NSManagedObject>(of entity: T.Type, filesAt directory: URL? = nil) async throws {
		try await waitUntilStoreLoaded()

		var quarantinedDirectory: (original: URL, quarantine: URL)?
		if let directory, FileManager.default.fileExists(atPath: directory.path) {
			let quarantine = directory.deletingLastPathComponent()
				.appendingPathComponent(".\(directory.lastPathComponent).deleting-\(UUID().uuidString)", isDirectory: true)
			try await Task.detached(priority: .utility) {
				try FileManager.default.moveItem(at: directory, to: quarantine)
			}.value
			quarantinedDirectory = (directory, quarantine)
		}

		let backgroundContext = makeBackgroundContext()
		do {
			try await backgroundContext.perform {
				let request = NSFetchRequest<T>(entityName: String(describing: entity))
				for object in try backgroundContext.fetch(request) {
					backgroundContext.delete(object)
				}
				if backgroundContext.hasChanges {
					try backgroundContext.save()
				}
			}
		} catch {
			await backgroundContext.perform {
				backgroundContext.rollback()
			}
			if let quarantinedDirectory {
				do {
					try await Task.detached(priority: .utility) {
						try FileManager.default.moveItem(
							at: quarantinedDirectory.quarantine,
							to: quarantinedDirectory.original
						)
					}.value
				} catch {
					Logger.misc.error("Could not restore Library files after a failed reset (error code \(error._code)).")
					throw StorageDeleteError.fileRestoreFailed
				}
			}
			throw error
		}

		if let quarantinedDirectory {
			do {
				try await Task.detached(priority: .utility) {
					try FileManager.default.removeItem(at: quarantinedDirectory.quarantine)
				}.value
			} catch {
				Logger.misc.error("Library records were reset, but quarantined files could not be removed (error code \(error._code)).")
				throw StorageDeleteError.fileCleanupFailed
			}
		}
	}

	func countContent<T: NSManagedObject>(for type: T.Type) -> String {
		let request = T.fetchRequest()
		return "\((try? context.count(for: request)) ?? 0)"
	}

	private static func _loadManagedObjectModel() -> NSManagedObjectModel? {
		for bundle in [Bundle(for: Storage.self), Bundle.main] {
			guard
				let modelURL = bundle.url(forResource: "Feather", withExtension: "momd")
					?? bundle.url(forResource: "Feather", withExtension: "mom"),
				let model = NSManagedObjectModel(contentsOf: modelURL)
			else { continue }
			return model
		}
		return nil
	}

	private func _loadPersistentStore() {
		container.loadPersistentStores { [weak self] _, error in
			Task { @MainActor in
				self?._finishLoading(error: error)
			}
		}
	}

	private func _finishLoading(error: Error?) {
		guard case .loading = _storeLoadState else { return }

		let result: Result<Void, Error>
		if let error {
			storeLoadError = error
			_storeLoadState = .failed(error)
			result = .failure(error)
			Logger.misc.error("Core Data store could not be opened (error code \(error._code)); no store or Library files were deleted.")
		} else {
			_storeLoadState = .loaded
			isStoreLoaded = true
			result = .success(())
		}

		let waiters = _storeLoadWaiters
		_storeLoadWaiters.removeAll()
		for waiter in waiters {
			waiter.resume(with: result)
		}
	}
}

private enum StorageInitializationError: LocalizedError {
	case modelNotFound

	var errorDescription: String? {
		"Odysseus couldn't find its Core Data model in the app bundle. The existing Library was not modified."
	}
}

private enum StorageDeleteError: LocalizedError {
	case fileRestoreFailed
	case fileCleanupFailed

	var errorDescription: String? {
		switch self {
		case .fileRestoreFailed:
			return "Library files couldn't be restored after the reset failed; they remain in a hidden recovery directory."
		case .fileCleanupFailed:
			return "Library records were reset, but quarantined app files couldn't be removed and remain in a hidden recovery directory."
		}
	}
}
