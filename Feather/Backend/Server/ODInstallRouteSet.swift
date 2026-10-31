//
//  ODInstallRouteSet.swift
//  Odysseus
//
//  The local install server has to listen on all interfaces: in "Semi Local"
//  mode the manifest and payload URLs point at the device's LAN address, and
//  the system installer fetches them from there. Rebinding to loopback would
//  break that transport, so reachability stays as it is.
//
//  What changes is guessability. The manifest, payload, icons and install
//  page all live under a per-install random secret, so another host on the
//  network cannot enumerate the payload while the server is up. The secret
//  is generated once per `ServerInstaller` and only ever appears in the
//  URLs handed to the system installer.
//

import Foundation
import Security

/// One of the endpoints an install needs.
enum ODInstallRoute: Equatable {
	case manifest
	case payload
	case smallIcon
	case largeIcon
	case installPage
}

struct ODInstallRouteSet: Equatable {
	let secret: String
	let id: UUID

	init(secret: String, id: UUID) {
		self.secret = secret
		self.id = id
	}

	/// 128 bits of randomness, hex encoded. Falls back to UUID material if
	/// the system RNG is unavailable, which keeps the server usable rather
	/// than failing the install.
	static func makeSecret() -> String {
		var bytes = [UInt8](repeating: 0, count: 16)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		guard status == errSecSuccess else {
			return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
		}
		return bytes.map { String(format: "%02x", $0) }.joined()
	}

	/// Secrets are hex and between 8 and 64 characters; used by tests and by
	/// the invariant that a route set is only built from generated material.
	static func isWellFormedSecret(_ secret: String) -> Bool {
		(8...64).contains(secret.count) && secret.allSatisfy { $0.isHexDigit }
	}

	private var _base: String {
		"/\(secret)/\(id.uuidString)"
	}

	/// Resolves a request path.
	///
	/// Matching is exact equality against generated paths, so a request cannot
	/// reach anything else the process can read and `..` cannot match.
	func route(for path: String) -> ODInstallRoute? {
		if path == plistPath { return .manifest }
		if path == payloadPath { return .payload }
		if path == smallImagePath { return .smallIcon }
		if path == largeImagePath { return .largeIcon }
		if path == installPath { return .installPage }
		return nil
	}

	var plistPath: String { _base + ".plist" }
	var payloadPath: String { _base + ".ipa" }
	var smallImagePath: String { "/\(secret)/app57x57.png" }
	var largeImagePath: String { "/\(secret)/app512x512.png" }
	var installPath: String { "/\(secret)/install" }
}
