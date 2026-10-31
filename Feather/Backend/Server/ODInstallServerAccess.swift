//
//  ODInstallServerAccess.swift
//  Odysseus
//
//  Where the install server listens, and which requests it answers.
//
//  The server used to bind `0.0.0.0`, so it was reachable on every interface
//  the device had while an install was running, including cellular. It now
//  binds the same address that appears in the manifest URL: loopback when the
//  transport is loopback, otherwise the device's LAN address. The one case
//  that cannot be narrowed is a fully-local TLS identity configured with a
//  DNS name — a name cannot be bound — and that stays on `0.0.0.0` with the
//  request guard and the per-install secret as the controls.
//
//  Routing itself is scoped by `ODInstallRouteSet`: every sensitive path
//  carries a 128-bit secret, which is the credential. This type adds the
//  transport-level checks around it.
//

import Foundation

enum ODInstallServerAccess {
	static let loopback = "127.0.0.1"
	static let allInterfaces = "0.0.0.0"

	/// Address the listener binds to.
	///
	/// Must match the host used in `ServerInstaller.sni()`, otherwise the URL
	/// handed to iOS points somewhere the server is not listening.
	///
	/// - Parameters:
	///   - serverMethod: `1` is the plain-HTTP "Semi Local" transport.
	///   - usesLoopbackFix: the transport's `ipFix` switch, which advertises
	///     loopback instead of the LAN address.
	///   - localAddress: the device's LAN IPv4 address, if any.
	///   - tlsHostname: the hostname of the fully-local TLS identity, if any.
	static func bindHost(
		serverMethod: Int,
		usesLoopbackFix: Bool,
		localAddress: String?,
		tlsHostname: String?
	) -> String {
		if serverMethod == 1 {
			if usesLoopbackFix {
				return loopback
			}
			return ipv4(localAddress) ?? loopback
		}

		guard let tlsHostname else {
			return loopback
		}
		if let address = ipv4(tlsHostname) {
			return address
		}
		if tlsHostname.lowercased() == "localhost" {
			return loopback
		}
		// A custom DNS name can only be served on every interface.
		return allInterfaces
	}

	/// Whether a request may be answered.
	///
	/// - Only `GET` is served: the routes are read-only.
	/// - When a `Host` header is present it must name the address the server
	///   advertises. Every browser sends `Host`, so a page on another origin
	///   cannot reach the payload through DNS rebinding. A client that omits
	///   `Host` is still served: the 128-bit route secret is the credential,
	///   and rejecting hostless requests would only risk breaking an install.
	static func isAcceptableRequest(
		method: String,
		hostHeader: String?,
		expectedHost: String
	) -> Bool {
		guard method.uppercased() == "GET" else {
			return false
		}

		guard let hostHeader, !hostHeader.isEmpty else {
			return true
		}

		let host = hostComponent(of: hostHeader)
		guard !host.isEmpty else {
			return false
		}
		return host == expectedHost.lowercased()
	}

	/// Strips the port from a `Host` header value.
	///
	/// `192.168.1.5:4000` becomes `192.168.1.5`; `[::1]:4000` becomes `[::1]`.
	static func hostComponent(of header: String) -> String {
		let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		if trimmed.hasPrefix("[") {
			guard let end = trimmed.firstIndex(of: "]") else {
				return trimmed
			}
			return String(trimmed[trimmed.startIndex...end])
		}
		if let colon = trimmed.firstIndex(of: ":") {
			return String(trimmed[trimmed.startIndex..<colon])
		}
		return trimmed
	}

	/// Returns the value when it is a dotted-quad IPv4 address.
	///
	/// Interface addresses and user-supplied TLS hostnames are checked before
	/// either is used as a bind address.
	static func ipv4(_ value: String?) -> String? {
		guard let value, !value.isEmpty else {
			return nil
		}

		let parts = value.split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count == 4 else {
			return nil
		}

		for part in parts {
			guard
				!part.isEmpty,
				part.count <= 3,
				part.allSatisfy({ $0.isASCII && $0.isNumber }),
				let number = Int(part),
				(0...255).contains(number)
			else {
				return nil
			}
		}

		return value
	}
}
