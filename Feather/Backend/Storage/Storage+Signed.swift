//
//  Storage+Signed.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import CoreData
import UIKit.UIImpactFeedbackGenerator

// MARK: - Signed Apps
extension Storage {
	/// Save a Signed record on a private context. The certificate relationship
	/// is resolved by UUID inside that context; no managed object is transferred.
	func addSignedAsync(
		uuid: String,
		certificateUUID: String? = nil,
		appName: String? = nil,
		appIdentifier: String? = nil,
		appVersion: String? = nil,
		appIcon: String? = nil,
		playsFeedback: Bool = true
	) async throws -> NSManagedObjectID {
		try await waitUntilStoreLoaded()
		let context = makeBackgroundContext()
		let objectID = try await context.perform {
			let signed = Signed(context: context)
			signed.uuid = uuid
			signed.date = Date()
			signed.identifier = appIdentifier
			signed.name = appName
			signed.icon = appIcon
			signed.version = appVersion

			if let certificateUUID {
				let request: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
				request.predicate = NSPredicate(format: "uuid == %@", certificateUUID)
				request.fetchLimit = 1
				signed.certificate = try context.fetch(request).first
			}

			try context.save()
			return signed.objectID
		}

		if playsFeedback {
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
		}
		return objectID
	}
}
