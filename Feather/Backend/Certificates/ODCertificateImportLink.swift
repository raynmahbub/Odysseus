//
//  ODCertificateImportLink.swift
//  Odysseus
//
//  Parses `odysseus://import-certificate` links.
//
//  The importer and the exporter did not agree on a format:
//
//  * `FR.exportCertificateAndOpenUrl` substitutes `$(PASSWORD)` with the
//    **raw** password, while this app's importer base64-decoded the
//    `password` parameter — so a link Odysseus produced could never be
//    imported back into Odysseus.
//  * The importer requires a provisioning profile, but the exporter never
//    emitted one.
//  * The importer decoded query values a second time with
//    `removingPercentEncoding` after `URLComponents` had already decoded
//    them, which corrupts any password containing `%`.
//
//  The parser below is the single place that decodes the link, so the format
//  is testable without UIKit, files or a device. Both encodings of the
//  password are accepted: the caller tries each candidate against the `.p12`
//  and only continues when one actually opens it.
//

import Foundation
import NimbleExtensions

struct ODCertificateImportLink {
	/// Decoded, still-untrusted contents of an import link.
	struct Fields: Equatable {
		let p12Data: Data
		let provisionData: Data
		/// Passwords to try against the `.p12`, most likely first. Never empty.
		let passwordCandidates: [String]
	}

	/// A `.p12` with a signing identity is tens of kilobytes; the cap exists so
	/// a hostile link cannot make the importer allocate without bound.
	static let maximumP12Bytes = 512 * 1024
	static let maximumProvisionBytes = 256 * 1024

	static let scheme = "odysseus"
	static let host = "import-certificate"

	static func parse(_ url: URL) throws -> Fields {
		guard url.scheme?.lowercased() == scheme else {
			throw ODCertificateImportError.unsupportedLink
		}
		guard url.host?.lowercased() == host else {
			throw ODCertificateImportError.unsupportedLink
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			throw ODCertificateImportError.malformedLink
		}

		// `URLComponents` has already percent-decoded every value. Decoding
		// again here would turn a password such as `50%25off` into `50%off`.
		let items = components.queryItems ?? []
		func value(_ name: String) -> String? {
			items.first(where: { $0.name.lowercased() == name })?.value
		}

		guard let p12Value = value("p12"), !p12Value.isEmpty else {
			throw ODCertificateImportError.missingField("p12")
		}
		guard let provisionValue = value("mobileprovision"), !provisionValue.isEmpty else {
			throw ODCertificateImportError.missingField("mobileprovision")
		}
		guard let passwordValue = value("password") else {
			throw ODCertificateImportError.missingField("password")
		}

		let p12Data = try _decodeField(p12Value, name: "p12", limit: maximumP12Bytes)
		let provisionData = try _decodeField(provisionValue, name: "mobileprovision", limit: maximumProvisionBytes)
		let candidates = passwordCandidates(
			from: passwordValue,
			declaredEncoding: value("password_encoding")
		)

		guard !candidates.isEmpty else {
			throw ODCertificateImportError.missingField("password")
		}

		return Fields(
			p12Data: p12Data,
			provisionData: provisionData,
			passwordCandidates: candidates
		)
	}

	/// Passwords to try, in order.
	///
	/// Producers that follow `FeatherApp`'s original documentation send the
	/// password base64-encoded; the exporter sends it raw. When the encoding is
	/// not declared, the base64 reading is tried first and the verbatim value
	/// second. Which one is correct is decided by the `.p12` itself, never by
	/// guessing: a candidate that does not open the key is discarded.
	static func passwordCandidates(from value: String?, declaredEncoding: String?) -> [String] {
		guard let value else { return [] }

		switch declaredEncoding?.lowercased() {
		case "raw", "plain", "utf8", "utf-8":
			return [value]
		case "base64":
			if let decoded = _decodeBase64String(value) {
				return [decoded]
			}
			// Declared base64 but not decodable: keep the verbatim value so the
			// `.p12` check can still reject it with a precise error.
			return [value]
		default:
			if let decoded = _decodeBase64String(value), decoded != value {
				var candidates = [decoded]
				if !value.isEmpty {
					candidates.append(value)
				}
				return candidates
			}
			return [value]
		}
	}

	// MARK: - Decoding

	private static func _decodeField(_ value: String, name: String, limit: Int) throws -> Data {
		guard !value.isEmpty else {
			throw ODCertificateImportError.emptyField(name)
		}
		// Base64 is 4 characters per 3 bytes; anything longer than this cannot
		// decode to an acceptable payload, so reject before allocating.
		guard value.utf8.count <= (limit / 3 + 1) * 4 + 4 else {
			throw ODCertificateImportError.tooLarge(name)
		}

		if let data = _decodeBase64(value) {
			guard data.count <= limit else {
				throw ODCertificateImportError.tooLarge(name)
			}
			guard !data.isEmpty else {
				throw ODCertificateImportError.emptyField(name)
			}
			return data
		}

		// Older producers percent-encoded a value that was already
		// percent-encoded. `%` cannot appear in valid base64, so a value that
		// still contains one is safe to decode once more.
		if value.contains("%"), let unescaped = value.removingPercentEncoding, unescaped != value {
			if let data = _decodeBase64(unescaped) {
				guard data.count <= limit else {
					throw ODCertificateImportError.tooLarge(name)
				}
				guard !data.isEmpty else {
					throw ODCertificateImportError.emptyField(name)
				}
				return data
			}
		}

		throw ODCertificateImportError.invalidBase64(name)
	}

	private static func _decodeBase64(_ value: String) -> Data? {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, !trimmed.contains("%") else { return nil }

		var padded = trimmed
		let remainder = padded.count % 4
		if remainder > 0 {
			padded += String(repeating: "=", count: 4 - remainder)
		}
		return Data(base64Encoded: padded)
	}

	private static func _decodeBase64String(_ value: String) -> String? {
		guard let data = _decodeBase64(value) else { return nil }
		return String(data: data, encoding: .utf8)
	}
}

enum ODCertificateImportError: LocalizedError, Equatable {
	case malformedLink
	case unsupportedLink
	case missingField(String)
	case emptyField(String)
	case invalidBase64(String)
	case tooLarge(String)
	/// None of the supplied passwords opened the `.p12`.
	case passwordRejected
	/// The provisioning profile could not be decoded.
	case profileUnreadable
	case storageFailed

	var errorDescription: String? {
		switch self {
		case .malformedLink:
			return .localized("This certificate link is malformed.")
		case .unsupportedLink:
			return .localized("This link doesn't contain a certificate Odysseus can import.")
		case .missingField(let field):
			switch field {
			case "p12":
				return .localized("This certificate link is missing the certificate file (.p12).")
			case "mobileprovision":
				return .localized("This certificate link is missing the provisioning profile.")
			case "password":
				return .localized("This certificate link is missing the password.")
			default:
				return .localized("This certificate link is missing a required part.")
			}
		case .emptyField(let field):
			return .localized("The %@ in this certificate link is empty.", arguments: _displayName(for: field))
		case .invalidBase64(let field):
			return .localized("The %@ in this certificate link isn't valid.", arguments: _displayName(for: field))
		case .tooLarge(let field):
			return .localized("The %@ in this certificate link is too large.", arguments: _displayName(for: field))
		case .passwordRejected:
			return .localized("The password for this certificate didn't work. Ask for a new export link.")
		case .profileUnreadable:
			return .localized("The provisioning profile in this link couldn't be read, so nothing was imported.")
		case .storageFailed:
			return .localized("Odysseus couldn't prepare this certificate for import. Nothing was saved.")
		}
	}

	/// Field names are the only detail carried into the message; values are
	/// never included, because they can contain key material or a password.
	private func _displayName(for field: String) -> String {
		switch field {
		case "p12":
			return .localized("certificate file")
		case "mobileprovision":
			return .localized("provisioning profile")
		case "password":
			return .localized("password")
		default:
			return .localized("value")
		}
	}
}
