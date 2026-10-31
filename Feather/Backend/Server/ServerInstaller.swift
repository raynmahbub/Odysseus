//
//  Server.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import Vapor
import NIOSSL
import NIOTLS
import SwiftUI
import IDeviceSwift

// The server handles requests away from the main thread. Keep only plain
// metadata here; never retain a Core Data app object in a Vapor route.
struct ServerAppSnapshot: Sendable {
	let identifier: String?
	let name: String?
	let version: String?
}

// MARK: - Class
class ServerInstaller: Identifiable, ObservableObject {
	let id: UUID
	/// All request paths live under a per-install secret so another host on
	/// the network cannot enumerate the payload while the server is up.
	let routeSet: ODInstallRouteSet
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false
	private var _lifetimeTask: Task<Void, Never>?

	/// Longest an install server may stay up. A payload is streamed in
	/// seconds; this exists so a cancelled or forgotten install cannot leave a
	/// listener running indefinitely.
	static let maximumLifetime: TimeInterval = 10 * 60
	
	var packageUrl: URL?
	let app: ServerAppSnapshot
	@ObservedObject var viewModel: InstallerStatusViewModel
	private var _server: Application?
	private(set) var startupError: Error?

	init(app: ServerAppSnapshot, viewModel: InstallerStatusViewModel, startServer: Bool = true) throws {
		let identifier = UUID()
		self.id = identifier
		self.routeSet = ODInstallRouteSet(secret: ODInstallRouteSet.makeSecret(), id: identifier)
		self.app = app
		self.viewModel = viewModel
		guard startServer else { return }

		let server = try setupApp(port: port)
		_server = server
		_configureRoutes()
		do {
			try server.server.start()
			_needsShutdown = true
			_startLifetimeTimer()
		} catch {
			server.shutdown()
			throw error
		}
	}

	private init(app: ServerAppSnapshot, viewModel: InstallerStatusViewModel, startupError: Error) {
		let identifier = UUID()
		self.id = identifier
		self.routeSet = ODInstallRouteSet(secret: ODInstallRouteSet.makeSecret(), id: identifier)
		self.app = app
		self.viewModel = viewModel
		self.startupError = startupError
	}

	static func make(app: ServerAppSnapshot, viewModel: InstallerStatusViewModel, startServer: Bool) -> ServerInstaller {
		do {
			return try ServerInstaller(app: app, viewModel: viewModel, startServer: startServer)
		} catch {
			let installer = ServerInstaller(app: app, viewModel: viewModel, startupError: error)
			DispatchQueue.main.async {
				viewModel.status = .broken(error)
			}
			return installer
		}
	}
	
	deinit {
		_lifetimeTask?.cancel()
		_shutdownServer()
	}
	
	private func _configureRoutes() {
		_server?.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }

			// Only GET is served, and a request that names a host must name
			// this server. Unknown, unauthenticated and secret-less paths all
			// get the same answer, so the server does not confirm what exists.
			guard
				ODInstallServerAccess.isAcceptableRequest(
					method: req.method.rawValue,
					hostHeader: req.headers[.host].first,
					expectedHost: self.sni()
				),
				let route = self.routeSet.route(for: req.url.path)
			else {
				return Response(status: .notFound)
			}

			switch route {
			case .manifest:
				self._updateStatus(.sendingManifest)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: self.installManifestData))

			case .smallIcon:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: self.displayImageSmallData))

			case .largeIcon:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: self.displayImageLargeData))

			case .payload:
				guard let packageUrl = self.packageUrl else {
					return Response(status: .notFound)
				}

				self._updateStatus(.sendingPayload)

				return req.fileio.streamFile(
					at: packageUrl.path
				) { result in
					switch result {
					case .success:
						self._updateStatus(.installing)
						// The payload is delivered; nothing else is served
						// from this listener, so it can go away shortly.
						self._stopAfterPayloadDelivered()
					case .failure(let error):
						self._updateStatus(.broken(error))
					}
				}

			case .installPage:
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			}
		}
	}

	/// Stops the listener a short while after the payload has been delivered,
	/// so the last bytes can drain before the socket closes.
	private func _stopAfterPayloadDelivered() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
			self?.stop()
		}
	}

	private func _startLifetimeTimer() {
		_lifetimeTask?.cancel()
		_lifetimeTask = Task { @MainActor [weak self] in
			try? await Task.sleep(nanoseconds: UInt64(Self.maximumLifetime * 1_000_000_000))
			guard !Task.isCancelled else { return }
			self?.stop()
		}
	}

	/// Stops the listener.
	///
	/// Called when the install reaches a terminal state, when the payload has
	/// been delivered, when the install UI goes away, and when the lifetime
	/// timer expires — so the server never outlives the install that needed it.
	func stop() {
		_lifetimeTask?.cancel()
		_lifetimeTask = nil
		DispatchQueue.main.async { [weak self] in
			self?._shutdownServer()
		}
	}

	private func _shutdownServer() {
		guard _needsShutdown else { return }
		
		_needsShutdown = false
		_server?.server.shutdown()
		_server?.shutdown()
	}
	
	private func _updateStatus(_ newStatus: InstallerStatusViewModel.InstallerStatus) {
		DispatchQueue.main.async {
			self.viewModel.status = newStatus
		}
	}
		
	func getServerMethod() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	}
	
	func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}
}
