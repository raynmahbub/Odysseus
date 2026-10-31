//
//  ODCertificateExport.swift
//  Odysseus
//
//  Builds the `odysseus://export-certificate` callback URL.
//
//  The previous implementation substituted the certificate and its password
//  into a caller-supplied template by plain string replacement: the
//  certificate was escaped, the password was not. A password containing
//  `&`, `+`, `#`, `%` or a space therefore corrupted the URL, and the raw
//  secret ended up in whatever received the link. Everything here is pure
//  so it can be covered by tests.
//

import Foundation

enum ODCertificateExport {
	/// Characters left unescaped. Deliberately stricter than
	/// `.urlQueryAllowed`, which keeps characters such as `#` and `%` that
	/// would corrupt a password or a base64 blob.
	private static let _unreserved = CharacterSet(
		charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	)

	/// `UIApplication.open` silently fails on very long URLs; a 5–10 KB
	/// `.p12` plus query noise fits comfortably below this.
	static let maximumURLLength = 8_192

	/// Percent-encodes everything outside the unreserved set.
	static func encode(_ value: String) -> String? {
		value.addingPercentEncoding(withAllowedCharacters: _unreserved)
	}

	/// Substitutes the placeholders into the template and validates the result.
	///
	/// `$(BASE64_CERT)` is required — without it nothing would be exported.
	/// `$(PASSWORD)` is optional so a caller that only wants the archive still
	/// works.
	///
	/// Returns `nil` when the template is malformed or when the resulting URL
	/// is too long for `openURL` to handle.
	static func makeURL(
		template: String,
		certificateBase64: String,
		password: String
	) -> URL? {
		guard
			template.contains("$(BASE64_CERT)"),
			let encodedCertificate = encode(certificateBase64)
		else {
			return nil
		}

		guard let encodedPassword = encode(password) else {
			return nil
		}

		let urlString = template
			.replacingOccurrences(of: "$(BASE64_CERT)", with: encodedCertificate)
			.replacingOccurrences(of: "$(PASSWORD)", with: encodedPassword)

		guard
			urlString.count <= maximumURLLength,
			let url = URL(string: urlString),
			let scheme = url.scheme,
			!scheme.isEmpty
		else {
			return nil
		}

		return url
	}

	/// Short, human-readable destination shown in the confirmation alert so
	/// the user can see where the certificate is about to go.
	static func destinationDescription(for url: URL) -> String {
		let scheme = url.scheme ?? "?"
		guard let host = url.host, !host.isEmpty else {
			return "\(scheme)://"
		}
		return "\(scheme)://\(host)"
	}
}
