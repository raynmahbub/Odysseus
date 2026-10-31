//
//  IPAHandler.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import Foundation
import Zip
import SwiftUI
import OSLog
import NimbleExtensions

final class AppFileHandler: NSObject, @unchecked Sendable {
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	private let _uniqueWorkDir: URL
	var uniqueWorkDirPayload: URL?

	private var _ipa: URL
	private let _install: Bool
	private let _download: Download?

	init(
		file ipa: URL,
		install: Bool = false,
		download: Download? = nil
	) {
		self._ipa = ipa
		self._install = install
		self._download = download
		self._uniqueWorkDir = _fileManager.temporaryDirectory
			.appendingPathComponent("FeatherImport_\(_uuid)", isDirectory: true)

		super.init()
		Logger.misc.debug("Import initiated for: \(self._ipa.lastPathComponent) with ID: \(self._uuid)")
	}

	func copy() async throws {
		try _fileManager.createDirectoryIfNeeded(at: _uniqueWorkDir)

		let destinationURL = _uniqueWorkDir.appendingPathComponent(_ipa.lastPathComponent)
		try _fileManager.removeFileIfNeeded(at: destinationURL)
		try _fileManager.copyItem(at: _ipa, to: destinationURL)
		_ipa = destinationURL
		Logger.misc.info("[\(self._uuid)] File copied to temporary import storage.")
	}

	func extract() async throws {
		if _ipa.pathExtension == "ipa" {
			Zip.addCustomFileExtension("ipa")
		}
		if _ipa.pathExtension == "tipa" {
			Zip.addCustomFileExtension("tipa")
		}

		let download = self._download
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .utility).async {
				do {
					try Zip.unzipFile(
						self._ipa,
						destination: self._uniqueWorkDir,
						overwrite: true,
						password: nil,
						progress: { progress in
							if let download {
								DispatchQueue.main.async {
									download.unpackageProgress = progress
									#if !targetEnvironment(macCatalyst)
									if #available(iOS 26.0, *) {
										BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.overallProgress)
										}
									#endif
								}
							}
						}
					)

					self.uniqueWorkDirPayload = self._uniqueWorkDir.appendingPathComponent("Payload")
					continuation.resume()
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}

	func move() async throws {
		guard let payloadURL = uniqueWorkDirPayload else {
			throw ImportedFileHandlerError.payloadNotFound
		}

		let destinationURL = try await _directory()
		guard _fileManager.fileExists(atPath: payloadURL.path) else {
			throw ImportedFileHandlerError.payloadNotFound
		}

		try _fileManager.moveItem(at: payloadURL, to: destinationURL)
		Logger.misc.info("[\(self._uuid)] Moved extracted Payload to the import directory.")
		try? _fileManager.removeItem(at: _uniqueWorkDir)
	}

	func addToDatabase() async throws {
		let appDirectory = try await _directory()
		do {
			guard
				let appURL = _fileManager.getPath(in: appDirectory, for: "app"),
				let bundle = Bundle(url: appURL),
				let identifier = bundle.bundleIdentifier,
				!identifier.isEmpty
			else {
				throw ImportedFileHandlerError.appBundleNotFound
			}
			guard !bundle.name.isEmpty, !bundle.version.isEmpty else {
				throw ImportedFileHandlerError.invalidBundleMetadata
			}

			let objectID = try await Storage.shared.addImportedAsync(
				uuid: _uuid,
				appName: bundle.name,
				appIdentifier: identifier,
				appVersion: bundle.version,
				appIcon: bundle.iconFileName
			)
			Logger.misc.info("[\(self._uuid)] Added imported app record.")

			// Only the permanent object ID and immutable notification values cross
			// back to the main context; the managed object stays on its queue.
			let uuid = _uuid
			let isRemote = !(_download?.onlyArchiving ?? true)
			let downloadID = _download?.id
			await MainActor.run {
				var userInfo: [String: Any] = [
					"remote": isRemote,
					"managedObjectID": objectID
				]
				if let downloadID {
					userInfo["downloadID"] = downloadID
				}
				NotificationCenter.default.post(
					name: .odysseusDidImportApp,
					object: uuid,
					userInfo: userInfo
				)
			}
		} catch {
			// Don't leave an app directory that has no Library record.
			do {
				try await Task.detached(priority: .utility) {
					try FileManager.default.removeFileIfNeeded(at: appDirectory)
				}.value
			} catch {
				Logger.misc.error("Could not remove imported app files after a failed Library save (error code \(error._code)).")
			}
			throw error
		}
	}

	private func _directory() async throws -> URL {
		// Documents/Feather/Unsigned/\(UUID)
		_fileManager.unsigned(_uuid)
	}

	func clean() async throws {
		try _fileManager.removeFileIfNeeded(at: _uniqueWorkDir)
	}
}

extension Notification.Name {
	/// object: imported app UUID (String); userInfo["managedObjectID"]: permanent Core Data ID;
	/// userInfo["downloadID"]: the Download id, if any; userInfo["remote"]: download origin.
	static let odysseusDidImportApp = Notification.Name("Odysseus.didImportApp")
}

private enum ImportedFileHandlerError: LocalizedError {
	case payloadNotFound
	case appBundleNotFound
	case invalidBundleMetadata

	var errorDescription: String? {
		switch self {
		case .payloadNotFound: return .localized("The archive doesn't contain a usable Payload directory.")
		case .appBundleNotFound: return .localized("The imported app bundle couldn't be found.")
		case .invalidBundleMetadata: return .localized("The imported app is missing its name, identifier, or version.")
		}
	}
}
