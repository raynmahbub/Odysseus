//
//  ZsignHandler.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import Foundation
import ZsignSwift
import UIKit

/// Plain signing inputs that can safely cross the detached signing task.
/// The password is never logged or written to a diagnostics stream.
struct ODSigningOverride: Sendable {
	let p12Path: String
	let p12Password: String
	let provisionPath: String
	let certificateUUID: String?

	init(p12Path: String, p12Password: String, provisionPath: String, certificateUUID: String? = nil) {
		self.p12Path = p12Path
		self.p12Password = p12Password
		self.provisionPath = provisionPath
		self.certificateUUID = certificateUUID
	}
}

enum ODZsignOutcome {
	static func validate(returned: Bool, callbackSuccess: Bool?, callbackError: Error?) throws {
		if let callbackError {
			throw callbackError
		}
		guard returned else {
			throw SigningFileHandlerError.signFailed
		}
		guard let callbackSuccess else {
			throw SigningFileHandlerError.signCallbackMissing
		}
		guard callbackSuccess else {
			throw SigningFileHandlerError.signFailed
		}
	}
}

final class ZsignHandler {
	private let _appUrl: URL
	private let _options: Options
	private let _override: ODSigningOverride?

	init(
		appUrl: URL,
		options: Options = OptionsManager.shared.options,
		identityOverride: ODSigningOverride? = nil
	) {
		self._appUrl = appUrl
		self._options = options
		self._override = identityOverride
	}

	func disinject() async throws {
		guard !_options.disInjectionFiles.isEmpty else {
			return
		}

		let bundle = Bundle(url: _appUrl)
		let execPath = _appUrl.appendingPathComponent(bundle?.exec ?? "").relativePath

		if !Zsign.removeDylibs(appExecutable: execPath, using: _options.disInjectionFiles) {
			throw SigningFileHandlerError.disinjectFailed
		}
	}

	func sign() async throws {
		guard let identity = _override else {
			throw SigningFileHandlerError.missingCertifcate
		}
		try _runSign(identity: identity, adhoc: false)
	}

	func adhocSign() async throws {
		try _runSign(identity: nil, adhoc: true)
	}

	private func _runSign(identity: ODSigningOverride?, adhoc: Bool) throws {
		var callbackSuccess: Bool?
		var callbackError: Error?

		let returned: Bool
		if let identity {
			returned = Zsign.sign(
				appPath: _appUrl.path,
				provisionPath: identity.provisionPath,
				p12Path: identity.p12Path,
				p12Password: identity.p12Password,
				entitlementsPath: _options.appEntitlementsFile?.path ?? "",
				removeProvision: !_options.removeProvisioning,
				completion: { success, error in
					callbackSuccess = success
					callbackError = error
				}
			)
		} else {
			returned = Zsign.sign(
				appPath: _appUrl.path,
				entitlementsPath: _options.appEntitlementsFile?.path ?? "",
				adhoc: adhoc,
				removeProvision: !_options.removeProvisioning,
				completion: { success, error in
					callbackSuccess = success
					callbackError = error
				}
			)
		}

		try ODZsignOutcome.validate(
			returned: returned,
			callbackSuccess: callbackSuccess,
			callbackError: callbackError
		)

		// Zsign reports its signing result and separately confirms that the
		// main Mach-O contains a signature. Its checkSigned API is a presence
		// check, not a cryptographic signature validator.
		guard
			let bundle = Bundle(url: _appUrl),
			let executableURL = bundle.executableURL,
			Zsign.checkSigned(appExecutable: executableURL.path)
		else {
			throw SigningFileHandlerError.signatureCheckFailed
		}
	}
}
