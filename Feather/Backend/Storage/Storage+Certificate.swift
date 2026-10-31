//
//  Storage+Certificate.swift
//  Feather
//
//  Created by samara on 16.04.2025.
//

import CoreData
import OSLog
import UIKit.UIImpactFeedbackGenerator
import ZsignSwift

// MARK: - Class extension: certificate
extension Storage {
	func addCertificate(
		uuid: String,
		password: String? = nil,
		nickname: String? = nil,
		ppq: Bool = false,
		expiration: Date,
		isDefault: Bool = false,
		playsFeedback: Bool = true,
		checksRevocation: Bool = true,
		completion: @escaping (Error?) -> Void
	) {
		// The `.p12` password is a secret: keep it out of the Core Data store.
		// Store it first, so a keychain refusal leaves no half-created record.
		if let password, !password.isEmpty {
			do {
				try certificatePasswords.setPassword(password, for: uuid)
			} catch {
				Logger.misc.error("[\(uuid)] Could not store the certificate password securely.")
				completion(error)
				return
			}
		}

		let generator = playsFeedback ? UIImpactFeedbackGenerator(style: .light) : nil

		let new = CertificatePair(context: context)
		new.uuid = uuid
		new.date = Date()
		// Legacy field, intentionally empty. `password(for:)` reads the secret
		// from the keychain and migrates any value written by older builds.
		new.password = nil
		new.ppQCheck = ppq
		new.expiration = expiration
		new.nickname = nickname
		new.isDefault = isDefault
		saveContext()
		if checksRevocation {
			Task { @MainActor in
				await ODCertificateStatusStore.shared.check(new)
				ODExpiryReminderScheduler.reschedule()
			}
		}
		generator?.impactOccurred()
		completion(nil)
	}

	/// Resolves the `.p12` password for a certificate.
	///
	/// Reads the keychain first. When an older build left a password in the
	/// Core Data attribute, that value is moved into the keychain and the
	/// attribute is cleared, so the migration happens on first use rather than
	/// needing a dedicated upgrade step.
	func password(for cert: CertificatePair) -> String? {
		guard let uuid = cert.uuid else {
			return cert.password
		}

		if let stored = certificatePasswords.password(for: uuid) {
			if cert.password != nil {
				cert.password = nil
				saveContext()
			}
			return stored
		}

		guard let legacy = cert.password, !legacy.isEmpty else {
			return nil
		}

		do {
			try certificatePasswords.setPassword(legacy, for: uuid)
			cert.password = nil
			saveContext()
		} catch {
			// Leave the legacy value in place rather than losing it; the next
			// read tries again.
			Logger.misc.error("[\(uuid)] Could not migrate the stored certificate password to the keychain.")
		}
		return legacy
	}

	/// Deletes a certificate and its key material.
	///
	/// The record is only removed once the files are gone. If the `.p12`
	/// directory cannot be removed the record is kept and `false` is returned,
	/// so a failed deletion cannot leave an orphaned private key behind a UI
	/// that says the certificate is gone.
	@discardableResult
	func deleteCertificate(for cert: CertificatePair) -> Bool {
		if let uuid = cert.uuid {
			do {
				// Removal is restricted to a direct child of the certificate
				// root, so a damaged `uuid` cannot delete unrelated files.
				try ODCertificateFiles.removeDirectory(for: uuid)
			} catch let error as CocoaError where error.code == .fileNoSuchFile {
				// Already removed; nothing left to protect.
			} catch {
				Logger.misc.error("[\(uuid)] Could not remove certificate files; keeping the record.")
				return false
			}
		}

		if let uuid = cert.uuid {
			certificatePasswords.removePassword(for: uuid)
		}
		context.delete(cert)
		saveContext()
		return true
	}

	func getCertificate(for index: Int) -> CertificatePair? {
		let fetchRequest: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]

		guard
			let results = try? context.fetch(fetchRequest),
			index >= 0 && index < results.count
		else {
			return nil
		}
		
		return results[index]
	}
	
	/// Odysseus: kept for older call sites; runs a real OCSP check.
	func revokagedCertificate(for cert: CertificatePair) {
		Task { @MainActor in
			await ODCertificateStatusStore.shared.check(cert)
		}
	}
	
	enum FileRequest: String {
		case certificate = "p12"
		case provision = "mobileprovision"
	}
	
	func getFile(_ type: FileRequest, from cert: CertificatePair) -> URL? {
		guard let url = getUuidDirectory(for: cert) else {
			return nil
		}
		
		return FileManager.default.getPath(in: url, for: type.rawValue)
	}
	
	func getProvisionFileDecoded(for cert: CertificatePair) -> Certificate? {
		guard let url = getFile(.provision, from: cert) else {
			return nil
		}
		
		let read = CertificateReader(url)
		return read.decoded
	}
	
	func getUuidDirectory(for cert: CertificatePair) -> URL? {
		guard let uuid = cert.uuid else {
			return nil
		}
		
		return FileManager.default.certificates(uuid)
	}
	
	func getAllCertificates() -> [CertificatePair] {
		let fetchRequest: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
		return (try? context.fetch(fetchRequest)) ?? []
	}

	func selectedCertificateIndex(matching selector: String) -> Int? {
		let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !selector.isEmpty else {
			return nil
		}

		let certificates = getAllCertificates()
		if let index = Int(selector), certificates.indices.contains(index) {
			return index
		}

		let normalizedSelector = selector.lowercased()
		for (index, certificate) in certificates.enumerated() {
			let decoded = getProvisionFileDecoded(for: certificate)
			let candidates = [
				certificate.uuid,
				certificate.nickname,
				decoded?.UUID,
				decoded?.Name,
				decoded?.AppIDName,
				decoded?.TeamName
			]

			if candidates.contains(where: { $0?.lowercased() == normalizedSelector }) {
				return index
			}

			if decoded?.TeamIdentifier.contains(where: { $0.lowercased() == normalizedSelector }) == true {
				return index
			}
		}

		return nil
	}
}
