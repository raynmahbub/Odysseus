//
//  Storage+Imported.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import CoreData
import UIKit.UIImpactFeedbackGenerator

// MARK: - Imported Apps
extension Storage {
	/// Insert and save on a private context. Only the permanent object ID
	/// crosses back to the caller; the managed object stays on its queue.
	func addImportedAsync(
		uuid: String,
		source: URL? = nil,
		appName: String? = nil,
		appIdentifier: String? = nil,
		appVersion: String? = nil,
		appIcon: String? = nil,
		playsFeedback: Bool = true
	) async throws -> NSManagedObjectID {
		try await waitUntilStoreLoaded()
		let context = makeBackgroundContext()
		let objectID = try await context.perform {
			let imported = Imported(context: context)
			imported.uuid = uuid
			imported.source = source
			imported.date = Date()
			imported.identifier = appIdentifier
			imported.name = appName
			imported.icon = appIcon
			imported.version = appVersion
			try context.save()
			return imported.objectID
		}

		if playsFeedback {
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
		}
		return objectID
	}
}
