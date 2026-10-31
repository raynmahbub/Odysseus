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
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false
	
	var packageUrl: URL?
	let app: ServerAppSnapshot
	@ObservedObject var viewModel: InstallerStatusViewModel
	private var _server: Application?
	private(set) var startupError: Error?

	init(app: ServerAppSnapshot, viewModel: InstallerStatusViewModel, startServer: Bool = true) throws {
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
			switch req.url.path {
			case plistEndpoint.path:
				self._updateStatus(.sendingManifest)
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: installManifestData))
			case displayImageSmallEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
			case displayImageLargeEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
			case payloadEndpoint.path:
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
			case "/install":
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			default:
				return Response(status: .notFound)
			}
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
