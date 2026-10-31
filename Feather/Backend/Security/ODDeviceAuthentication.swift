//
//  ODDeviceAuthentication.swift
//  Odysseus
//
//  Device-owner authentication for actions that release signing key
//  material (currently: exporting a certificate to another app).
//
//  The app already asked for Face ID before exporting an Apple ID
//  certificate; this puts the same gate in front of imported certificates.
//  When the device has no passcode configured the evaluation cannot run, so
//  the caller is told "no" and must fail closed.
//

import Foundation
import LocalAuthentication

enum ODDeviceAuthentication {
	/// Asks for biometrics or the device passcode.
	/// - Returns: `true` only when the device owner authenticated.
	static func authenticate(reason: String) async -> Bool {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
			return false
		}

		return await withCheckedContinuation { continuation in
			context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
				continuation.resume(returning: success)
			}
		}
	}
}
