//
//  Server+TLS.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import NIOSSL
import NIOTLS
import Vapor
import SystemConfiguration.CaptiveNetwork

// MARK: Setup
extension ServerInstaller {
	static let env: Environment = {
		var env = try! Environment.detect()
		try! LoggingSystem.bootstrap(from: &env)
		return env
	}()

	func setupApp(port: Int) throws -> Application {
		let app = Application(Self.env)
		app.threadPool = .init(numberOfThreads: 1)

		if getServerMethod() != 1 {
			// Fully Local mode must have a valid user-owned identity. Never
			// downgrade the advertised HTTPS endpoint to an unencrypted server.
			app.http.server.configuration.tlsConfiguration = try tls()
		}

		// Bind the same address the manifest advertises instead of every
		// interface. See `ODInstallServerAccess.bindHost` for the one case
		// (a custom TLS DNS name) that still has to listen on all of them.
		let bindHost = ODInstallServerAccess.bindHost(
			serverMethod: getServerMethod(),
			usesLoopbackFix: getIPFix(),
			localAddress: Self.getLocalAddress(),
			tlsHostname: ODLocalServerTLS.hostname
		)

		app.http.server.configuration.hostname = sni()
		app.http.server.configuration.tcpNoDelay = true
		app.http.server.configuration.address = .hostname(bindHost, port: port)
		app.http.server.configuration.port = port
		app.routes.defaultMaxBodySize = "128mb"
		app.routes.caseInsensitive = false

		return app
	}

	// MARK: Files/IP
	func sni() -> String {
		let localhost = "127.0.0.1"

		if getServerMethod() == 1 {
			return !self.getIPFix()
				? (Self.getLocalAddress() ?? localhost)
				: localhost
		}
		return ODLocalServerTLS.hostname ?? localhost
	}

	func tls() throws -> TLSConfiguration {
		try ODLocalServerTLS.tlsConfiguration()
	}

	func readCommonName() -> String? {
		ODLocalServerTLS.hostname
	}
}

extension ServerInstaller {
	static func getLocalAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?

		if getifaddrs(&ifaddr) == 0 {
			var ptr = ifaddr
			while ptr != nil {
				let interface = ptr!.pointee
				let addrFamily = interface.ifa_addr.pointee.sa_family

				if addrFamily == UInt8(AF_INET) {
					let name = String(cString: interface.ifa_name)
					if name == "en0" || name == "pdp_ip0" {
						var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
						if getnameinfo(
							interface.ifa_addr,
							socklen_t(interface.ifa_addr.pointee.sa_len),
							&hostname,
							socklen_t(hostname.count),
							nil,
							socklen_t(0),
							NI_NUMERICHOST
						) == 0 {
							address = String(cString: hostname)
						}
					}
				}
				ptr = ptr!.pointee.ifa_next
			}
			freeifaddrs(ifaddr)
		}

		return address
	}
}
