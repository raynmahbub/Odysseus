//
//  CertificateFileHandler.swift
//  Feather
//
//  Created by samara on 15.04.2025.
//

import Foundation
import OSLog
import NimbleExtensions

final class CertificateFileHandler: NSObject {
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	
	private let _key: URL
	private let _provision: URL
	private let _keyPassword: String?
	private let _certNickname: String?
	private let _isDefault: Bool
	private let _playsFeedback: Bool
	private let _checksRevocation: Bool
	
	private var _certPair: Certificate?
	
	init(
		key: URL,
		provision: URL,
		password: String? = nil,
		nickname: String? = nil,
		isDefault: Bool = false,
		playsFeedback: Bool = true,
		checksRevocation: Bool = true
	) {
		self._key = key
		self._provision = provision
		self._keyPassword = password
		self._certNickname = nickname
		self._isDefault = isDefault
		self._playsFeedback = playsFeedback
		self._checksRevocation = checksRevocation
		
		_certPair = CertificateReader(provision).decoded
		
		super.init()
	}
	
	func copy() async throws {
		guard
			(_certPair != nil)
		else {
			throw CertificateFileHandlerError.certNotValid
		}

		let destinationURL = try await _directory()

		let copiedKey = destinationURL.appendingPathComponent(_key.lastPathComponent)
		let copiedProvision = destinationURL.appendingPathComponent(_provision.lastPathComponent)
		do {
			try _fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
			try _fileManager.copyItem(at: _key, to: copiedKey)
			try _fileManager.copyItem(at: _provision, to: copiedProvision)
		} catch {
			// A half-copied directory must not survive a failed import.
			try? ODCertificateFiles.removeDirectory(for: _uuid)
			throw error
		}

		// The `.p12` holds the signing private key: owner-only permissions,
		// `completeUntilFirstUserAuthentication`, and no backup.
		ODCertificateFiles.protect(directory: destinationURL)
	}
	
	@MainActor
	func addToDatabase() async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			Storage.shared.addCertificate(
				uuid: _uuid,
				password: _keyPassword,
				nickname: _certNickname,
				ppq: _certPair?.PPQCheck ?? false,
				expiration: _certPair?.ExpirationDate ?? Date(),
				isDefault: _isDefault,
				playsFeedback: _playsFeedback,
				checksRevocation: _checksRevocation
			) { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			}
		}
		Logger.misc.info("[\(self._uuid)] Added to database")
	}

	/// Removes the copied `.p12`/profile when the database write failed, so a
	/// failed import cannot leave key material behind without a record.
	///
	/// Only the directory this import created is removed; `ODCertificateFiles`
	/// refuses anything that is not a direct child of the certificate root.
	func cleanup() {
		do {
			try ODCertificateFiles.removeDirectory(for: _uuid)
		} catch {
			Logger.misc.error("Could not remove the files of a failed certificate import (error code \(error._code)).")
		}
	}

	private func _directory() async throws -> URL {
		do {
			return try ODCertificateFiles.directory(for: _uuid)
		} catch {
			throw CertificateFileHandlerError.invalidDestination
		}
	}
}

enum CertificateFileHandlerError: LocalizedError {
	case certNotValid
	case invalidDestination

	var errorDescription: String? {
		switch self {
		case .certNotValid:
			return .localized("This provisioning profile couldn't be read, so the certificate wasn't imported.")
		case .invalidDestination:
			return .localized("Odysseus couldn't find a safe place to store this certificate, so nothing was imported.")
		}
	}
}
