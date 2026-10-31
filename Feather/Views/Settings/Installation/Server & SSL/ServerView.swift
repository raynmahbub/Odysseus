//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleViews
import UniformTypeIdentifiers
import NimbleExtensions
import OSLog

struct ServerView: View {
	@AppStorage("Feather.ipFix") private var _ipFix = false
	@AppStorage("Feather.serverMethod") private var _serverMethod = 0

	@State private var _hostname = ""
	@State private var _certificateData: Data?
	@State private var _privateKeyData: Data?
	@State private var _certificateName: String?
	@State private var _privateKeyName: String?
	@State private var _isImportingCertificate = false
	@State private var _isImportingPrivateKey = false
	@State private var _isShowingMessage = false
	@State private var _message = ""

	private let _serverMethods: [String] = [.localized("Fully Local"), .localized("Semi Local")]

	private var _pemType: UTType { UTType(filenameExtension: "pem") ?? .data }
	private var _certificateType: UTType { UTType(filenameExtension: "crt") ?? _pemType }
	private var _privateKeyType: UTType { UTType(filenameExtension: "key") ?? _pemType }

	var body: some View {
		Group {
			Section {
				Picker(.localized("Server Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods.indices, id: \.description) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}

			if _serverMethod == 0 {
				Section {
					TextField(.localized("Certificate Hostname"), text: $_hostname)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
						.keyboardType(.URL)

					Button {
						_isImportingCertificate = true
					} label: {
						Label(
							_certificateName ?? String.localized("Select Certificate Chain (.pem or .crt)"),
							systemImage: "checkmark.seal"
						)
					}

					Button {
						_isImportingPrivateKey = true
					} label: {
						Label(
							_privateKeyName ?? String.localized("Select Private Key (.pem or .key)"),
							systemImage: "key.horizontal"
						)
					}

					Button(.localized("Save TLS Identity"), systemImage: "lock.shield") {
						_saveIdentity()
					}
					.disabled(_certificateData == nil || _privateKeyData == nil || _hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

					if ODLocalServerTLS.hostname != nil {
						Button(.localized("Remove Saved TLS Identity"), systemImage: "trash", role: .destructive) {
							_removeIdentity()
						}
					}
				} header: {
					Text(.localized("Fully Local TLS"))
				} footer: {
					Text(.localized("Import a PEM certificate chain and matching unencrypted PEM private key you control. The hostname must be covered by a currently trusted server certificate and resolve to this device. The private key is stored with file protection, restricted permissions, and backup exclusion; it is never bundled or downloaded by Odysseus."))
				}
			} else {
				Section {
					Text(.localized("Semi Local mode uses the existing external HTTPS plist server and does not need a TLS identity in Odysseus."))
						.foregroundStyle(.secondary)
				}
			}
		}
		.onAppear {
			_hostname = ODLocalServerTLS.hostname ?? ""
		}
		.sheet(isPresented: $_isImportingCertificate) {
			FileImporterRepresentableView(
				allowedContentTypes: [_certificateType, _pemType],
				onDocumentsPicked: { urls in
					if let url = urls.first { _loadIdentityFile(url, isPrivateKey: false) }
				}
			)
			.ignoresSafeArea()
		}
		.sheet(isPresented: $_isImportingPrivateKey) {
			FileImporterRepresentableView(
				allowedContentTypes: [_privateKeyType, _pemType],
				onDocumentsPicked: { urls in
					if let url = urls.first { _loadIdentityFile(url, isPrivateKey: true) }
				}
			)
			.ignoresSafeArea()
		}
		.alert(.localized("Local Server TLS"), isPresented: $_isShowingMessage) {
			Button(.localized("OK"), role: .cancel) {}
		} message: {
			Text(_message)
		}
	}

	private func _loadIdentityFile(_ url: URL, isPrivateKey: Bool) {
		let hasSecurityScope = url.startAccessingSecurityScopedResource()
		defer {
			if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
			// The picker is configured with asCopy=true, so remove its sandbox
			// copy after reading rather than retaining private-key material there.
			do {
				try FileManager.default.removeItem(at: url)
			} catch {
				Logger.misc.error("Could not remove temporary TLS picker copy (error code \(error._code)).")
			}
		}

		do {
			let data = try Data(contentsOf: url)
			guard !data.isEmpty else { throw ODLocalServerTLSError.unreadableIdentity }
			if isPrivateKey {
				_privateKeyData = data
				_privateKeyName = url.lastPathComponent
			} else {
				_certificateData = data
				_certificateName = url.lastPathComponent
			}
		} catch {
			_message = error.localizedDescription
			_isShowingMessage = true
		}
	}

	private func _saveIdentity() {
		guard let certificateData = _certificateData, let privateKeyData = _privateKeyData else { return }
		do {
			try ODLocalServerTLS.installIdentity(
				certificateData: certificateData,
				privateKeyData: privateKeyData,
				hostname: _hostname
			)
			_message = .localized("TLS identity saved. Certificate validation remains enabled.")
		} catch {
			_message = error.localizedDescription
		}
		_certificateData = nil
		_privateKeyData = nil
		_certificateName = nil
		_privateKeyName = nil
		_isShowingMessage = true
	}

	private func _removeIdentity() {
		do {
			try ODLocalServerTLS.removeIdentity()
			_hostname = ""
			_message = .localized("The saved TLS identity was removed.")
		} catch {
			_message = .localized("The saved TLS identity could not be removed.")
		}
		_isShowingMessage = true
	}
}
