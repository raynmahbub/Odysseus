//
//  FR.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import Foundation.NSURL
import UIKit.UIImage
import Zsign
import NimbleJSON
import AltSourceKit
import IDeviceSwift
import NimbleExtensions

enum FR {
	static func handlePackageFile(
		_ ipa: URL,
		download: Download? = nil,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = AppFileHandler(file: ipa, download: download)
			
			do {
				try await handler.copy()
				try await handler.extract()
				try await handler.move()
				try await handler.addToDatabase()
				try? await handler.clean()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				try? await handler.clean()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	@MainActor
	static func signPackageFile(
		appURL: URL,
		using options: Options,
		icon: UIImage?,
		identityOverride: ODSigningOverride? = nil,
		completion: @escaping (Error?, String?) -> Void
	) {
		let iconData = icon?.pngData()
		Task.detached {
			let handler = SigningHandler(sourceAppURL: appURL, options: options)
			handler.signingOverride = identityOverride
			handler.appIconData = iconData

			do {
				try await handler.copy()
				try await handler.modify()
				try? await handler.clean()
				let signedUUID = handler.signedUUID
				await MainActor.run {
					completion(nil, signedUUID)
				}
			} catch {
				try? await handler.clean()
				await MainActor.run {
					completion(error, nil)
				}
			}
		}
	}
	
	static func handleCertificateFiles(
		p12URL: URL,
		provisionURL: URL,
		p12Password: String,
		certificateName: String = "",
		isDefault: Bool = false,
		playsFeedback: Bool = true,
		checksRevocation: Bool = true,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			let handler = CertificateFileHandler(
				key: p12URL,
				provision: provisionURL,
				password: p12Password,
				nickname: certificateName.isEmpty ? nil : certificateName,
				isDefault: isDefault,
				playsFeedback: playsFeedback,
				checksRevocation: checksRevocation
			)
			
			do {
				try await handler.copy()
				try await handler.addToDatabase()
				await MainActor.run {
					completion(nil)
				}
			} catch {
				// The record was not created: do not leave the copied `.p12`
				// and profile behind without one.
				handler.cleanup()
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
	
	static func checkPasswordForCertificate(
		for key: URL,
		with password: String,
		using provision: URL
	) -> Bool {
		defer {
			password_check_fix_WHAT_THE_FUCK_free(provision.path)
		}
		
		password_check_fix_WHAT_THE_FUCK(provision.path)
		
		if (!p12_password_check(key.path, password)) {
			return false
		}
		
		return true
	}
	
	static func movePairing(_ url: URL) {
		let fileManager = FileManager.default
		let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
		
		try? fileManager.removeFileIfNeeded(at: dest)
		
		try? fileManager.copyItem(at: url, to: dest)
		
		HeartbeatManager.shared.start(true)
	}
	
	static func handleSource(
		_ urlString: String,
		competion: @escaping () -> Void
	) {
		guard let url = URL(string: urlString) else { return }

		NBFetchService().fetch(from: url) { (result: Result<ASRepository, Error>) in
			Task { @MainActor in
				switch result {
				case .success(let data):
					let id = data.id ?? url.absoluteString
					if !Storage.shared.sourceExists(id) {
						Storage.shared.addSource(url, repository: data, id: id) { _ in
							competion()
						}
					} else {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Repository already added."))
					}
				case .failure(let error):
					UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
				}
			}
		}
	}

	@MainActor
	static func exportCertificateAndOpenUrl(using template: String) {
		// Validate the template once and work out where the certificate would
		// actually go, so the confirmation can name the destination instead of
		// asking the user to trust an opaque link.
		guard
			let previewURL = ODCertificateExport.makeURL(
				template: template,
				certificateBase64: "",
				password: ""
			)
		else {
			UIAlertController.showAlertWithOk(
				title: .localized("Couldn't export"),
				message: .localized("The certificate link is not valid.")
			)
			return
		}

		let destination = ODCertificateExport.destinationDescription(for: previewURL)

		func performExport(for certificate: CertificatePair) {
			guard
				let certificateKeyFile = Storage.shared.getFile(.certificate, from: certificate),
				let certificateKeyFileData = try? Data(contentsOf: certificateKeyFile)
			else {
				return
			}

			guard
				let callbackURL = ODCertificateExport.makeURL(
					template: template,
					certificateBase64: certificateKeyFileData.base64EncodedString(),
					password: Storage.shared.password(for: certificate) ?? ""
				)
			else {
				// Refusing is safer than handing over a truncated link.
				UIAlertController.showAlertWithOk(
					title: .localized("Couldn't export"),
					message: .localized("This certificate is too large to hand over as a link.")
				)
				return
			}

			UIApplication.shared.open(callbackURL)
		}

		let certificates = Storage.shared.getAllCertificates()
		guard !certificates.isEmpty else { return }

		DispatchQueue.main.async {
			var selectionActions: [UIAlertAction] = []

			for cert in certificates {
				var title: String
				let decoded = Storage.shared.getProvisionFileDecoded(for: cert)

				title = cert.nickname ?? decoded?.Name ?? .localized("Unknown")

				if let getTaskAllow = decoded?.Entitlements?["get-task-allow"]?.value as? Bool, getTaskAllow == true {
					title = "🐞 \(title)"
				}

				let selectAction = UIAlertAction(title: title, style: .default) { _ in
					Task { @MainActor in
						// The `.p12` is the signing identity: require the device
						// owner before it leaves the app, and fail closed when no
						// passcode is configured.
						guard await ODDeviceAuthentication.authenticate(
							reason: .localized("Export your signing certificate")
						) else {
							UIAlertController.showAlertWithOk(
								title: .localized("Authentication needed"),
								message: .localized("Confirm it's you before exporting a certificate. If this device has no passcode, set one first.")
							)
							return
						}

						performExport(for: cert)
					}
				}
				selectionActions.append(selectAction)
			}

			UIAlertController.showAlertWithCancel(
				title: .localized("Export Certificate"),
				message: .localized("Do you want to export your certificate to an external app? That app will be able to sign apps using your certificate.\n\nDestination: %@", arguments: destination),
				style: .alert,
				actions: selectionActions
			)
		}
	}

}
