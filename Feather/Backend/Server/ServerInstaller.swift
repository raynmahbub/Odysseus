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
		_shutdownServer()
	}
	
	private func _configureRoutes() {
		_server?.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }
			let path = req.url.path
			let routes = self.routeSet

			if path == routes.plistPath {
				self._updateStatus(.sendingManifest)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: installManifestData))
			}

			if path == routes.smallImagePath {
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
			}

			if path == routes.largeImagePath {
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
			}

			if path == routes.payloadPath {
				guard let packageUrl = packageUrl else {
					return Response(status: .notFound)
				}

				self._updateStatus(.sendingPayload)

				return req.fileio.streamFile(
					at: packageUrl.path
				) { result in
					switch result {
					case .success:
						self._updateStatus(.installing)
					case .failure(let error):
						self._updateStatus(.broken(error))
					}

				}
			}

			if path == routes.installPath {
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			}

			return Response(status: .notFound)
		}
	}

	/// Stops the listener. Called when the install reaches a terminal state so
	/// the server does not outlive the install that needed it.
	func stop() {
		_shutdownServer()
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
