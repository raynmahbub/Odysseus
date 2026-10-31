//
//  ODCertificateFiles.swift
//  Odysseus
//
//  Where `.p12` and provisioning-profile material lives, and how it is
//  protected at rest.
//
//  Certificates used to be stored in `Documents/Certificates/<uuid>`. Because
//  the app sets `UIFileSharingEnabled`, that directory is visible in the Files
//  app and over iTunes/Finder file sharing, it carries the default data
//  protection class, and it is included in device backups. The `.p12` holds
//  the signing private key, so none of those properties are acceptable.
//
//  Material now lives in `Library/Application Support/Odysseus/Certificates`,
//  which is not user-visible, is marked excluded from backup, and is written
//  with `completeUntilFirstUserAuthentication` protection and owner-only POSIX
//  permissions. `completeUntilFirstUserAuthentication` is used rather than
//  `complete` because an install can finish (and then be signed) while the
//  device is locked in the background; a stricter class would make those reads
//  fail instead of protecting anything meaningful.
//
//  This does not encrypt anything: it uses the platform's existing file
//  protection and backup-exclusion mechanisms only.
//

import Foundation
import OSLog
import NimbleExtensions

enum ODCertificateFiles {
	/// Directory name inside the app's container, for both roots.
	static let directoryName = "Certificates"

	/// `Application Support/Odysseus/Certificates`.
	/// Single source of truth for the path: `FileManager.certificates`.
	static var root: URL {
		FileManager.default.certificates
	}

	/// The pre-migration location, `Documents/Certificates`.
	static var legacyRoot: URL {
		FileManager.default.legacyCertificates
	}

	// MARK: - Names

	/// A certificate directory name is a UUID string. This check exists to make
	/// path traversal impossible, not to validate UUID syntax, so any single
	/// path component that is not `.`/`..` and contains no separator is
	/// accepted — records written by older builds must still be deletable.
	static func isSafeName(_ name: String) -> Bool {
		guard !name.isEmpty, name.utf8.count <= 128 else { return false }
		guard name != ".", name != ".." else { return false }
		return !name.contains("/") && !name.contains("\\") && !name.contains("\0")
	}

	/// Directory for one certificate, guaranteed to be a direct child of `root`.
	static func directory(for name: String) throws -> URL {
		guard isSafeName(name) else {
			throw ODCertificateFilesError.unsafeName
		}
		return root.appendingPathComponent(name, isDirectory: true)
	}

	// MARK: - Preparation and migration

	/// Creates the protected root, migrates legacy material, and re-applies
	/// protection to everything already stored there.
	///
	/// Idempotent and safe to call on every launch. Never overwrites or deletes
	/// a directory that is already present at the destination.
	static func prepare() {
		let fileManager = FileManager.default
		do {
			try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
		} catch {
			Logger.misc.error("Could not create the certificate directory (error code \(error._code)).")
			return
		}

		protect(directory: root)
		migrateLegacyMaterial()
		protectExistingDirectories()
	}

	/// Moves `Documents/Certificates/*` into the protected root.
	///
	/// The legacy directory is only removed when it is empty, so anything the
	/// user or another feature left there is preserved.
	static func migrateLegacyMaterial() {
		let fileManager = FileManager.default
		let legacy = legacyRoot
		var isDirectory: ObjCBool = false
		guard
			fileManager.fileExists(atPath: legacy.path, isDirectory: &isDirectory),
			isDirectory.boolValue
		else {
			return
		}

		let children = (try? fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
		for child in children {
			let name = child.lastPathComponent
			guard isSafeName(name) else { continue }

			let destination = root.appendingPathComponent(name, isDirectory: true)
			guard !fileManager.fileExists(atPath: destination.path) else { continue }

			do {
				try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
				try fileManager.moveItem(at: child, to: destination)
				protect(directory: destination)
			} catch {
				Logger.misc.error("Could not move stored certificate material into the protected directory (error code \(error._code)).")
			}
		}

		if let remaining = try? fileManager.contentsOfDirectory(atPath: legacy.path), remaining.isEmpty {
			try? fileManager.removeItem(at: legacy)
		}
	}

	private static func protectExistingDirectories() {
		let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
		for child in children {
			protect(directory: child)
		}
	}

	// MARK: - Protection

	/// Applies backup exclusion and file protection to a certificate directory
	/// and its contents.
	static func protect(directory url: URL) {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
			return
		}
		guard isDirectory.boolValue else {
			protect(file: url)
			return
		}

		var values = URLResourceValues()
		values.isExcludedFromBackup = true
		var mutable = url
		try? mutable.setResourceValues(values)

		try? FileManager.default.setAttributes(
			[
				.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
				.posixPermissions: 0o700,
			],
			ofItemAtPath: url.path
		)

		let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
		for item in contents {
			protect(file: item)
		}
	}

	/// Applies only the file-level attributes. Directories stay owner-only.
	static func protect(file url: URL) {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
			return
		}

		do {
			try FileManager.default.setAttributes(
				[
					.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
					.posixPermissions: isDirectory.boolValue ? 0o700 : 0o600,
				],
				ofItemAtPath: url.path
			)
		} catch {
			Logger.misc.error("Could not apply file protection to stored certificate material (error code \(error._code)).")
		}

		if isDirectory.boolValue {
			var values = URLResourceValues()
			values.isExcludedFromBackup = true
			var mutable = url
			try? mutable.setResourceValues(values)
		}
	}

	// MARK: - Removal

	enum RemovalOutcome: Equatable {
		case removed
		case missing
	}

	/// Removes one certificate directory.
	///
	/// Refuses anything that is not a direct child of the certificate root, so a
	/// corrupted or hostile name cannot delete unrelated files. A missing
	/// directory is reported, not treated as a failure.
	@discardableResult
	static func removeDirectory(for name: String) throws -> RemovalOutcome {
		let directory = try directory(for: name)
		let fileManager = FileManager.default

		let rootPath = root.standardizedFileURL.path
		let directoryPath = directory.standardizedFileURL.path
		guard
			directory.deletingLastPathComponent().standardizedFileURL.path == rootPath,
			directoryPath.hasPrefix(rootPath + "/")
		else {
			throw ODCertificateFilesError.unsafeName
		}

		var isDirectory: ObjCBool = false
		guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory) else {
			return .missing
		}
		guard isDirectory.boolValue else {
			throw ODCertificateFilesError.unsafeName
		}

		try fileManager.removeItem(at: directory)
		return .removed
	}

	// MARK: - Temporary import copies

	private static let temporaryPrefix = "OdysseusImport-"

	/// Writes an import payload to a protected temporary file.
	///
	/// The caller owns the returned URL and must pass it to
	/// `removeTemporary(_:)` on success, failure and cancellation.
	static func writeTemporaryProtected(_ data: Data, pathExtension: String) throws -> URL {
		let name = "\(temporaryPrefix)\(UUID().uuidString).\(pathExtension)"
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
		try data.write(to: url, options: .atomic)
		protect(file: url)
		return url
	}

	/// Deletes a temporary import file.
	///
	/// Only files this type created, inside the system temporary directory, are
	/// touched: a URL that came from somewhere else (a document picker result,
	/// a user-selected destination) is ignored.
	static func removeTemporary(_ url: URL) {
		let temporaryPath = FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"
		let path = url.standardizedFileURL.path
		guard
			path.hasPrefix(temporaryPath),
			url.lastPathComponent.hasPrefix(temporaryPrefix)
		else {
			return
		}
		try? FileManager.default.removeItem(at: url)
	}
}

enum ODCertificateFilesError: LocalizedError, Equatable {
	/// The supplied directory name is not a single safe path component.
	case unsafeName

	var errorDescription: String? {
		switch self {
		case .unsafeName:
			return .localized("The certificate's storage location is invalid, so it was left alone.")
		}
	}
}
