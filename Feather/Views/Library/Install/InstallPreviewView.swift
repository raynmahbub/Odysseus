//
//  InstallPreview.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog
import NimbleExtensions

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss

	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isWebviewPresenting = false
	@State private var progressTask: Task<Void, Never>?
	
	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	
	@State var isSharing: Bool
	
	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
		let viewModel = InstallerStatusViewModel(isIdevice: UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1)
		self._viewModel = StateObject(wrappedValue: viewModel)
		let hasServerMetadata = [app.identifier, app.name, app.version].allSatisfy { $0?.isEmpty == false }
		let needsServer = !isSharing
			&& UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 0
			&& hasServerMetadata
		let serverApp = ServerAppSnapshot(identifier: app.identifier, name: app.name, version: app.version)
		self._installer = StateObject(wrappedValue: ServerInstaller.make(app: serverApp, viewModel: viewModel, startServer: needsServer))
	}
	
	// MARK: Body
	var body: some View {
		let cornerRadius = {
			if #available(iOS 26.0, *) {
				28.0
			} else {
				10.5
			}
		}()
		
		ZStack {
			InstallProgressView(app: app, viewModel: viewModel)
			_status()
			_button()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(cornerRadius)
		.padding()
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			if _installationMethod == 0 {
				if case .ready = newStatus {
					if _serverMethod == 0 {
						if let installURL = URL(string: installer.iTunesLink) {
							UIApplication.shared.open(installURL)
						} else {
							viewModel.status = .broken(SigningFileHandlerError.invalidInstallationURL)
						}
					} else if _serverMethod == 1 {
						_isWebviewPresenting = true
					}
				}
				
				if case .sendingPayload = newStatus, _serverMethod == 1 {
					_isWebviewPresenting = false
				}
				
				if case .installing = newStatus, progressTask == nil {
					if let bundleID = installer.app.identifier {
						progressTask = startInstallProgressPolling(bundleID: bundleID, viewModel: viewModel)
					} else {
						viewModel.status = .broken(SigningFileHandlerError.appIdentifierNotFound)
					}
				}
				
				switch newStatus {
				case .completed, .broken(_):
					progressTask?.cancel()
					progressTask = nil
					// The install is over: stop listening instead of waiting for
					// the sheet to be deallocated.
					installer.stop()
					#if !targetEnvironment(macCatalyst)
					BackgroundAudioManager.shared.stop()
					#endif
				default:
					break
				}
			}
		}
		.onAppear(perform: _install)
		
		#if !targetEnvironment(macCatalyst)
		.onAppear {
			BackgroundAudioManager.shared.start()
		}
		#endif
		
		.onDisappear {
			progressTask?.cancel()
			progressTask = nil

			// Dismissing the sheet is a cancellation: the listener must not
			// keep running until the object happens to be deallocated.
			installer.stop()

			
			#if !targetEnvironment(macCatalyst)
			BackgroundAudioManager.shared.stop()
			#endif
		}
	}
	
	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton("Open", systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
	
	@MainActor
	private func _install() {
		if !isSharing, _installationMethod == 0, let error = installer.startupError {
			viewModel.status = .broken(error)
			UIAlertController.showAlertWithOk(
				title: .localized("Couldn't start local server"),
				message: error.localizedDescription
			)
			return
		}
		if !isSharing, _installationMethod == 0 {
			guard
				let identifier = installer.app.identifier, !identifier.isEmpty,
				let name = installer.app.name, !name.isEmpty,
				let version = installer.app.version, !version.isEmpty
			else {
				let error = SigningFileHandlerError.appMetadataNotFound
				viewModel.status = .broken(error)
				UIAlertController.showAlertWithOk(
					title: .localized("Couldn't install app"),
					message: error.localizedDescription
				)
				return
			}
		}

		let isSelfUpdate = Bundle.main.bundleIdentifier.map { app.identifier == $0 } ?? false
		guard isSharing || !isSelfUpdate || _installationMethod == 1 else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
			)
			return
		}
		guard let appURL = Storage.shared.getAppDirectory(for: app) else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: SigningFileHandlerError.appNotFound.localizedDescription
			)
			return
		}

		let snapshot = AppArchiveSnapshot(
			appURL: appURL,
			name: app.name,
			version: app.version,
			identifier: app.identifier
		)

		Task { @MainActor in
			do {
				let handler = ArchiveHandler(snapshot: snapshot, viewModel: viewModel)
				try await handler.move()
				let packageURL = try await handler.archive()

				if !isSharing {
					if _installationMethod == 0 {
						installer.packageUrl = packageURL
						viewModel.status = .ready
					} else if _installationMethod == 1 {
						let proxy = InstallationProxy(viewModel: viewModel)
						try await proxy.install(
							at: packageURL,
							suspend: snapshot.identifier == Bundle.main.bundleIdentifier
						)
					}
				} else {
					let package = try await handler.moveToArchive(packageURL, shouldOpen: !_useShareSheet)
					if !_useShareSheet {
						dismiss()
					} else {
						UIActivityViewController.show(activityItems: [package])
					}
				}
			} catch {
				progressTask?.cancel()
				UIAlertController.showAlertWithOk(
					title: .localized("Install"),
					message: error.localizedDescription,
					action: { HeartbeatManager.shared.start(true); dismiss() }
				)
			}
		}
	}
	
	private func startInstallProgressPolling(
		bundleID: String,
		viewModel: InstallerStatusViewModel
	) -> Task<Void, Never> {

		Task.detached(priority: .background) {
			var hasStarted = false

			while !Task.isCancelled {
				let rawProgress = await UIApplication.installProgress(for: bundleID) ?? 0.0

				if rawProgress > 0 {
					hasStarted = true
				}

				let progress = await hasStarted
					? _normalizeInstallProgress(rawProgress)
					: 0.0

				Logger.misc.info("Install progress for \(bundleID): \(progress)")

				await MainActor.run {
					viewModel.installProgress = progress
				}

				if hasStarted && rawProgress == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 1_000_000) // 1 ms
			}
		}
	}

	private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
		min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
	}
}
