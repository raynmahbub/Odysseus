//
//  ODInstallSheet.swift
//  Odysseus
//
//  Install sheet. Same machinery as Feather's InstallPreviewView
//  (ArchiveHandler → ServerInstaller or idevice over the pairing
//  file), with a progress ring around the app icon.
//

import SwiftUI
import IDeviceSwift
import NimbleViews
import OSLog
import NimbleExtensions

// MARK: - View
struct ODInstallSheet: View {
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
		VStack(spacing: 0) {
			Spacer()

			_progressRing

			VStack(spacing: 4) {
				Text(app.name ?? .localized("Unknown"))
					.font(.system(.headline, design: .rounded).weight(.bold))
					.lineLimit(1)

				Text(_statusText)
					.font(.subheadline)
					.foregroundStyle(_isBroken ? ODTheme.revoked : Color.secondary)
					.multilineTextAlignment(.center)
					.lineLimit(2)
					.animation(.smooth, value: _statusText)
			}
			.padding(.top, 18)
			.padding(.horizontal, 24)

			Spacer()

			if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					Label(.localized("Open App"), systemImage: "arrow.up.forward.app.fill")
				}
				.buttonStyle(ODProminentButtonStyle())
				.padding(.horizontal, 24)
				.padding(.bottom, 28)
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(ODTheme.navy.ignoresSafeArea())
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			if case .completed = newStatus {
				ODTheme.success()
			}

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

			#if !targetEnvironment(macCatalyst)
			BackgroundAudioManager.shared.stop()
			#endif
		}
	}

	// MARK: Presentation
	private var _isBroken: Bool {
		if case .broken = viewModel.status { return true }
		return false
	}

	private var _statusText: String {
		if isSharing {
			return viewModel.isCompleted
				? .localized("Saved")
				: .localized("Packaging a copy…")
		}

		if case .broken(let error) = viewModel.status {
			return error.localizedDescription
		}

		return viewModel.friendlyStatusLabel
	}

	@ViewBuilder
	private var _progressRing: some View {
		ZStack {
			Circle()
				.stroke(Color.accentColor.opacity(0.15), lineWidth: 5)
				.frame(width: 108, height: 108)

			Circle()
				.trim(from: 0, to: viewModel.isCompleted ? 1 : max(0.02, viewModel.overallProgress))
				.stroke(
					_isBroken ? ODTheme.revoked : Color.accentColor,
					style: StrokeStyle(lineWidth: 5, lineCap: .round)
				)
				.rotationEffect(.degrees(-90))
				.frame(width: 108, height: 108)
				.animation(.smooth, value: viewModel.overallProgress)

			FRAppIconView(app: app, size: 80)

			if viewModel.isCompleted {
				Image(systemName: "checkmark.circle.fill")
					.font(.title2)
					.symbolRenderingMode(.palette)
					.foregroundStyle(.white, .green)
					.background(Circle().fill(.white).padding(3))
					.offset(x: 38, y: 38)
					.compatTransition()
			}
		}
	}

	// MARK: Install
	@MainActor
	private func _install() {
		if !isSharing, _installationMethod == 0, let error = installer.startupError {
			viewModel.status = .broken(error)
			return
		}
		if !isSharing, _installationMethod == 0 {
			guard
				let identifier = installer.app.identifier, !identifier.isEmpty,
				let name = installer.app.name, !name.isEmpty,
				let version = installer.app.version, !version.isEmpty
			else {
				viewModel.status = .broken(SigningFileHandlerError.appMetadataNotFound)
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
			viewModel.status = .broken(SigningFileHandlerError.appNotFound)
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
				viewModel.status = .broken(error)
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

// MARK: - Status labels
extension InstallerStatusViewModel {
	var friendlyStatusLabel: String {
		let isPairing = UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1
		switch status {
		case .none: return .localized("Getting ready…")
		case .ready: return isPairing ? .localized("Connecting…") : .localized("Waiting for iOS…")
		case .sendingManifest, .sendingPayload: return .localized("Sending to iOS…")
		case .installing: return .localized("Installing…")
		case .completed: return .localized("Installed")
		case .broken: return .localized("Something went wrong")
		}
	}
}
