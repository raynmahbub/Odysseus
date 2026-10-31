//
//  FeatherApp.swift
//  Odysseus (based on Feather by samara, 10.04.2025)
//

import SwiftUI
import Nuke
import IDeviceSwift
import OSLog
import AltSourceKit
import NimbleExtensions

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
	let heartbeat = HeartbeatManager.shared
	
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject private var _sourceFetchErrorToast = SourceFetchErrorToastCenter.shared
	@Environment(\.scenePhase) private var _scenePhase
	@AppStorage("Feather.userTintColor") private var _tintHex: String = "#B8CCF0"
	@StateObject private var storage = Storage.shared

	var body: some Scene {
		WindowGroup {
			Group {
				if let error = storage.storeLoadError {
					ContentUnavailableView(
						.localized("Library unavailable"),
						systemImage: "externaldrive.badge.exclamationmark",
						description: Text(verbatim: String.localized("Odysseus couldn't open its Library database. Existing Library data was preserved. Restart the app and contact the developer if this continues. Error: %@", arguments: error.localizedDescription))
					)
				} else if storage.isStoreLoaded {
					ODRootView()
						.environment(\.managedObjectContext, storage.context)
				} else {
					ProgressView(.localized("Loading Library…"))
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				}
			}
			.tint(Color(hex: _tintHex))
				.animation(.smooth, value: downloadManager.manualDownloads.description)
				.overlay(alignment: .bottom) {
					if let message = _sourceFetchErrorToast.message {
						SourceFetchErrorToastView(
							message: message,
							systemImage: _sourceFetchErrorToast.systemImage
						)
						.padding(.bottom, 120)
					}
				}
				.animation(.spring(response: 0.28, dampingFraction: 0.9), value: _sourceFetchErrorToast.message)
				.onOpenURL(perform: _handleURL)
				.onReceive(NotificationCenter.default.publisher(for: .heartbeatInvalidHost)) { _ in
					DispatchQueue.main.async {
						UIAlertController.showAlertWithOk(
							title: "InvalidHostID",
							message: .localized("Your pairing file is invalid and is incompatible with your device, please import a valid pairing file.")
						)
					}
				}
				.onAppear {
					let window = UIApplication.topViewController()?.view.window
					if let style = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: ODPrefs.interfaceStyle)) {
						window?.overrideUserInterfaceStyle = style
					}
					window?.tintColor = UIColor(Color(hex: UserDefaults.standard.string(forKey: ODPrefs.tintColor) ?? ODTheme.moonlightHex))
				}
				.onChange(of: _scenePhase) { _, phase in
					guard phase == .active, storage.isStoreLoaded else { return }
					Task { @MainActor in
						await ODCertificateStatusStore.shared.checkAllIfNeeded()
						await ODCatalogStore.shared.refreshIfNeeded()
					}
				}
		}
	}
	
	@MainActor
	private func _handleURL(_ url: URL) {
		guard storage.isStoreLoaded else {
			UIAlertController.showAlertWithOk(
				title: .localized("Library unavailable"),
				message: .localized("The Library database isn't ready. Try again after it loads, or restart Odysseus if it failed to open.")
			)
			return
		}
		if url.scheme == "odysseus" {
			/// odysseus://select-certificate?cert=<nickname|uuid|profile-name|profile-uuid|team-name|index>
			/// odysseus://switch-certificate?cert=<nickname|uuid|profile-name|profile-uuid|team-name|index>
			if url.host == "select-certificate" || url.host == "switch-certificate" {
				_handleCertificateSelectionURL(url)
				return
			}
			/// odysseus://import-certificate?p12=<base64>&mobileprovision=<base64>&password=<base64|raw>
			/// Parsed and validated by `ODCertificateImportLink`; nothing is
			/// stored until the password opens the key and the user confirms.
			if url.host == "import-certificate" {
				_handleCertificateImportURL(url)
				return
			}
			/// odysseus://export-certificate?callback_template=<template>
			/// ?callback_template=: This is how we callback to the application requesting the certificate, this will be a url scheme
			/// 	example: livecontainer%3A%2F%2Fcertificate%3Fcert%3D%24%28BASE64_CERT%29%26password%3D%24%28PASSWORD%29
			/// 	decoded: livecontainer://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)
			/// $(BASE64_CERT) and $(PASSWORD) must be presenting in the callback template so we can replace them with the proper content
			if url.host == "export-certificate" {
				guard
					let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
				else {
					return
				}
				
				let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
				// `URLComponents` already decoded this once; see
				// `ODCertificateExport.resolveTemplate` for why a blind second
				// decode is wrong.
				guard let callbackTemplate = ODCertificateExport.resolveTemplate(queryItems["callback_template"]) else { return }

				FR.exportCertificateAndOpenUrl(using: callbackTemplate)
			}
			/// odysseus://source/<url>
			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { }
			}
			/// odysseus://install/<url.ipa>
			if
				let fullPath = url.validatedScheme(after: "/install/"),
				let downloadURL = URL(string: fullPath)
			{
				_ = DownloadManager.shared.startDownload(from: downloadURL)
			}
		} else {
			if url.pathExtension == "ipa" || url.pathExtension == "tipa" {
				if FileManager.default.isFileFromFileProvider(at: url) {
					guard url.startAccessingSecurityScopedResource() else { return }
					FR.handlePackageFile(url) { _ in }
				} else {
					FR.handlePackageFile(url) { _ in }
				}
				
				return
			}
		}
	}

	/// Imports a certificate from a deep link.
	///
	/// The link is untrusted input. It is decoded by
	/// `ODCertificateImportLink`, staged in protected temporary files, accepted
	/// only when one of the candidate passwords really opens the `.p12`, and
	/// then confirmed by name before anything reaches the Library. The staged
	/// files are removed on success, failure and cancellation.
	@MainActor
	private func _handleCertificateImportURL(_ url: URL) {
		let fields: ODCertificateImportLink.Fields
		do {
			fields = try ODCertificateImportLink.parse(url)
		} catch {
			_presentCertificateImportFailure(error)
			return
		}

		var temporaryURLs: [URL] = []
		func removeTemporaryFiles() {
			temporaryURLs.forEach(ODCertificateFiles.removeTemporary)
			temporaryURLs.removeAll()
		}

		let p12URL: URL
		let provisionURL: URL
		do {
			p12URL = try ODCertificateFiles.writeTemporaryProtected(fields.p12Data, pathExtension: "p12")
			temporaryURLs.append(p12URL)
			provisionURL = try ODCertificateFiles.writeTemporaryProtected(fields.provisionData, pathExtension: "mobileprovision")
			temporaryURLs.append(provisionURL)
		} catch {
			removeTemporaryFiles()
			Logger.misc.error("Could not stage a certificate import (error code \(error._code)).")
			_presentCertificateImportFailure(ODCertificateImportError.storageFailed)
			return
		}

		guard let decodedProfile = CertificateReader(provisionURL).decoded else {
			removeTemporaryFiles()
			_presentCertificateImportFailure(ODCertificateImportError.profileUnreadable)
			return
		}

		// Only a password that opens the key is accepted; everything else is
		// reported as a rejected password rather than as a bad file.
		guard let password = fields.passwordCandidates.first(where: { FR.passwordOpensKey($0, for: p12URL) }) else {
			removeTemporaryFiles()
			_presentCertificateImportFailure(ODCertificateImportError.passwordRejected)
			return
		}

		let generator = UINotificationFeedbackGenerator()
		generator.prepare()

		// `Certificate` models these as non-optional strings, so an empty
		// value means "the profile didn't say".
		let certificateName = !decodedProfile.Name.isEmpty
			? decodedProfile.Name
			: (!decodedProfile.AppIDName.isEmpty ? decodedProfile.AppIDName : .localized("Unnamed certificate"))
		let teamIdentifier = decodedProfile.TeamIdentifier.first ?? ""
		let teamName = !decodedProfile.TeamName.isEmpty
			? decodedProfile.TeamName
			: (!teamIdentifier.isEmpty ? teamIdentifier : .localized("unknown team"))

		UIAlertController.showAlert(
			title: .localized("Import Certificate?"),
			message: .localized(
				"“%@” (%@) will be added to your Library and can be used to sign apps. Only continue if you trust where this link came from.",
				arguments: certificateName,
				teamName
			),
			style: .alert,
			actions: [
				UIAlertAction(title: .localized("Import"), style: .default) { _ in
					FR.handleCertificateFiles(
						p12URL: p12URL,
						provisionURL: provisionURL,
						p12Password: password
					) { error in
						removeTemporaryFiles()
						if let error {
							generator.notificationOccurred(.error)
							UIAlertController.showAlertWithOk(
								title: .localized("Couldn't import"),
								message: error.localizedDescription
							)
						} else {
							generator.notificationOccurred(.success)
						}
					}
				},
				UIAlertAction(title: .localized("Cancel"), style: .cancel) { _ in
					removeTemporaryFiles()
				},
			]
		)
	}

	@MainActor
	private func _presentCertificateImportFailure(_ error: Error) {
		UINotificationFeedbackGenerator().notificationOccurred(.error)
		UIAlertController.showAlertWithOk(
			title: .localized("Couldn't import certificate"),
			message: error.localizedDescription
		)
	}

	@MainActor
	private func _handleCertificateSelectionURL(_ url: URL) {
		guard
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else {
			return
		}
		let queryItems = components.queryItems ?? []

		func queryValue(_ names: String...) -> String? {
			for name in names {
				if let value = queryItems.first(where: { $0.name.lowercased() == name })?.value?.removingPercentEncoding {
					return value
				}
			}
			return nil
		}

		let pathSelector = components.path
			.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
			.removingPercentEncoding

		guard
			let selector = queryValue("cert", "certificate", "name", "nickname", "uuid", "id", "index")
				?? (pathSelector?.isEmpty == false ? pathSelector : nil)
		else {
			return
		}

		let generator = UINotificationFeedbackGenerator()
		generator.prepare()

		guard let index = Storage.shared.selectedCertificateIndex(matching: selector) else {
			generator.notificationOccurred(.error)
			UIAlertController.showAlertWithOk(
				title: .localized("Certificate Not Found"),
				message: .localized("No certificate matches \"%@\".", arguments: selector)
			)
			return
		}

		UserDefaults.standard.set(index, forKey: "feather.selectedCert")
		generator.notificationOccurred(.success)
	}
}

class AppDelegate: NSObject, UIApplicationDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		ODPrefs.registerDefaults()
		ODLocalServerTLS.removeLegacySharedMaterial()
		ODCertificateFiles.prepare()
		_createPipeline()
		_createDocumentsDirectories()
		do {
			try ResetView.clearWorkCache()
		} catch {
			Logger.misc.error("Temporary work cache cleanup failed (error code \(error._code)).")
		}
		Task { @MainActor in
			ODAppleIDManager.cleanupStaleSigningMaterial()
			do {
				try await Storage.shared.waitUntilStoreLoaded()
				await _installStartupSources()
			} catch {
				Logger.misc.error("Startup services were skipped because the Library database is unavailable (error code \(error._code)).")
			}
		}
		return true
	}
	
	@MainActor
	private func _installStartupSources() async {
		var insertedCount = DefaultSourceInstaller.installIfNeeded()
		
		do {
			insertedCount += try await DefaultSourceInstaller.updateFromRemote()
		} catch {
			Logger.misc.error("Failed to update startup sources: \(error.localizedDescription)")
		}
		
		if insertedCount > 0 {
			SourceFetchErrorToastCenter.shared.show(
				.localized("Added %d sources", arguments: insertedCount),
				systemImage: "checkmark.circle.fill"
			)
		}
		
		await ODCatalogStore.shared.load()
		ODExpiryReminderScheduler.reschedule()
		await ODCertificateStatusStore.shared.checkAllIfNeeded()
	}

	private func _createPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0
		
		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "com.mirazbakis.Odysseus.datacache") // disk cache
			let imageCache = Nuke.ImageCache() // memory cache
			dataCache?.sizeLimit = 500 * 1024 * 1024
			imageCache.costLimit = 100 * 1024 * 1024
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .automatic
			$0.isStoringPreviewsInMemoryCache = false
		}
		
		ImagePipeline.shared = pipeline
	}
	
	private func _createDocumentsDirectories() {
		let fileManager = FileManager.default

		// `certificates` is created (and protected) by `ODCertificateFiles`,
		// outside the user-visible Documents tree.
		let directories: [URL] = [
			fileManager.archives,
			fileManager.signed,
			fileManager.unsigned
		]
		
		for url in directories {
			try? fileManager.createDirectoryIfNeeded(at: url)
		}
	}
	
}
