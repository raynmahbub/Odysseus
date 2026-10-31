//
//  ODCertificatePasswordStore.swift
//  Odysseus
//
//  Imported `.p12` passwords used to live in the Core Data
//  `CertificatePair.password` attribute, which is an ordinary SQLite file
//  inside the app container and is included in device backups and in the
//  Files-app view of Documents/.
//
//  They now live in the keychain, keyed by certificate UUID. The Core Data
//  attribute is kept in the model but is written as `nil`; existing records
//  are migrated the first time their password is read.
//

import Foundation
import Security
import NimbleExtensions

protocol ODCertificatePasswordStoring {
	func password(for uuid: String) -> String?
	/// Stores a non-empty password. Implementations must verify that the
	/// value really landed, because a silent keychain failure would
	/// otherwise be reported as success.
	func setPassword(_ password: String, for uuid: String) throws
	func removePassword(for uuid: String)
}

enum ODCertificatePasswordStoreError: LocalizedError {
	/// Deliberately carries no secret material.
	case writeFailed

	var errorDescription: String? {
		switch self {
		case .writeFailed:
			return .localized("The certificate password couldn't be stored securely. The certificate was not saved.")
		}
	}
}

/// Keychain-backed store built on the app's existing `ODKeychain` wrapper.
struct ODKeychainCertificatePasswordStore: ODCertificatePasswordStoring {
	static let shared = ODKeychainCertificatePasswordStore()

	private static let _prefix = "certificate-password."

	/// Callers should treat this as opaque; it is derived from a UUID.
	static func key(for uuid: String) -> String {
		_prefix + uuid
	}

	func password(for uuid: String) -> String? {
		ODKeychain.string(for: Self.key(for: uuid))
	}

	func setPassword(_ password: String, for uuid: String) throws {
		let key = Self.key(for: uuid)
		ODKeychain.setString(password, for: key)

		// `ODKeychain` discards the `SecItem*` status, so read the value
		// back before claiming the password was stored.
		guard ODKeychain.string(for: key) == password else {
			throw ODCertificatePasswordStoreError.writeFailed
		}
	}

	func removePassword(for uuid: String) {
		ODKeychain.setString(nil, for: Self.key(for: uuid))
	}
}
