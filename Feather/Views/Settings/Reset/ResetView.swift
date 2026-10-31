//
//  ResetView.swift
//  Feather
//
//  Created by samara on 19.06.2025.
//

import SwiftUI
import NimbleViews
import Nuke
import CoreData
import OSLog
import NimbleExtensions

// MARK: - View
struct ResetView: View {
	// MARK: Body
	var body: some View {
		NBList(.localized("Reset")) {
			_cache()
			_coredata()
			_all()
		}
	}
	
	private func _cacheSize() -> String {
		var totalCacheSize = URLCache.shared.currentDiskUsage
		if let nukeCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
			totalCacheSize += nukeCache.totalSize
		}
		return "\(ByteCountFormatter.string(fromByteCount: Int64(totalCacheSize), countStyle: .file))"
	}
	
	@MainActor
	static func resetAlert(
		title: String,
		message: String = "",
		action: @escaping @MainActor () async throws -> Void
	) {
		let alertAction = UIAlertAction(
			title: .localized("Proceed"),
			style: .destructive
		) { _ in
			Task { @MainActor in
				do {
					try await action()
					UIApplication.shared.suspendAndReopen()
				} catch {
					UIAlertController.showAlertWithOk(
						title: .localized("Reset failed"),
						message: .localized("Odysseus couldn't finish this reset. Completed operations remain in effect. Error: %@", arguments: error.localizedDescription)
					)
				}
			}
		}
		
		let style: UIAlertController.Style = UIDevice.current.userInterfaceIdiom == .pad
			? .alert
			: .actionSheet
		
		var msg = ""
		if !message.isEmpty { msg = message + "\n" }
		msg.append(.localized("This action cannot be undone. Would you like to proceed?"))
	
		UIAlertController.showAlertWithCancel(
			title: title,
			message: msg,
			style: style,
			actions: [alertAction]
		)
	}
}

// MARK: - View extension
extension ResetView {
	@ViewBuilder
	private func _cache() -> some View {
		Section {
			Button(.localized("Reset Work Cache"), systemImage: "xmark.rectangle.portrait") {
				Self.resetAlert(title: .localized("Reset Work Cache")) {
					try Self.clearWorkCache()
				}
			}
			
			Button(.localized("Reset Network Cache"), systemImage: "xmark.rectangle.portrait") {
				Self.resetAlert(
					title: .localized("Reset Network Cache"),
					message: _cacheSize()
				) {
					Self.clearNetworkCache()
				}
			}
		}
	}
	
	@ViewBuilder
	private func _coredata() -> some View {
		Section {
			Button(.localized("Reset Sources"), systemImage: "xmark.circle") {
				Self.resetAlert(
					title: .localized("Reset Sources"),
					message: Storage.shared.countContent(for: AltSource.self)
				) {
					try await Self.resetSources()
				}
			}
			
			Button(.localized("Reset Signed Apps"), systemImage: "xmark.circle") {
				Self.resetAlert(
					title: .localized("Reset Signed Apps"),
					message: Storage.shared.countContent(for: Signed.self)
				) {
					try await Self.deleteSignedApps()
				}
			}
			
			Button(.localized("Reset Imported Apps"), systemImage: "xmark.circle") {
				Self.resetAlert(
					title: .localized("Reset Imported Apps"),
					message: Storage.shared.countContent(for: Imported.self)
				) {
					try await Self.deleteImportedApps()
				}
			}
			
			Button(.localized("Reset Certificates"), systemImage: "xmark.circle") {
				Self.resetAlert(
					title: .localized("Reset Certificates"),
					message: Storage.shared.countContent(for: CertificatePair.self)
				) {
					try await Self.resetCertificates()
				}
			}
		}
	}
	
	@ViewBuilder
	private func _all() -> some View {
		Section {
			Button(.localized("Reset Settings"), systemImage: "xmark.octagon") {
				Self.resetAlert(title: .localized("Reset Settings")) {
					try Self.resetUserDefaults()
				}
			}
			
			Button(.localized("Reset All"), systemImage: "xmark.octagon") {
				Self.resetAlert(title: .localized("Reset All")) {
					try await Self.resetAll()
				}
			}
		}
		.foregroundStyle(.red)
	}
}

// MARK: - View extension: reset
extension ResetView {
	static func clearWorkCache() throws {
		let fileManager = FileManager.default
		let temporaryDirectory = fileManager.temporaryDirectory
		let files = try fileManager.contentsOfDirectory(
			at: temporaryDirectory,
			includingPropertiesForKeys: nil,
			options: [.skipsHiddenFiles]
		)
		for file in files where !file.lastPathComponent.hasPrefix("OdysseusAppleID_") {
			try fileManager.removeItem(at: file)
		}
	}

	static func clearNetworkCache() {
		URLCache.shared.removeAllCachedResponses()
		HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)

		if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
			dataCache.removeAll()
		}

		if let imageCache = ImagePipeline.shared.configuration.imageCache as? Nuke.ImageCache {
			imageCache.removeAll()
		}
	}

	@MainActor
	static func resetSources() async throws {
		try await Storage.shared.deleteAllRecords(of: AltSource.self)
	}

	@MainActor
	static func deleteSignedApps() async throws {
		try await Storage.shared.deleteAllRecords(of: Signed.self, filesAt: FileManager.default.signed)
	}

	@MainActor
	static func deleteImportedApps() async throws {
		try await Storage.shared.deleteAllRecords(of: Imported.self, filesAt: FileManager.default.unsigned)
	}

	@MainActor
	static func resetCertificates(resetAll: Bool = false) async throws {
		try await Storage.shared.deleteAllRecords(of: CertificatePair.self, filesAt: FileManager.default.certificates)
		if !resetAll {
			UserDefaults.standard.set(0, forKey: "feather.selectedCert")
		}
	}

	@MainActor
	static func resetUserDefaults() throws {
		guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
			throw ResetOperationError.missingBundleIdentifier
		}
		UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
	}

	@MainActor
	static func resetAll() async throws {
		try clearWorkCache()
		clearNetworkCache()
		try await resetSources()
		try await deleteSignedApps()
		try await deleteImportedApps()
		try await resetCertificates(resetAll: true)
		try resetUserDefaults()
	}
}

private enum ResetOperationError: LocalizedError {
	case missingBundleIdentifier

	var errorDescription: String? {
		"The app's bundle identifier is unavailable, so its settings could not be reset."
	}
}
