//
//  ODLocalServerTLS.swift
//  Odysseus
//
//  User-owned TLS identity for the fully-local installation server.
//  No shared key is downloaded or bundled.
//

import Foundation
import Security
import NIOSSL
import NIOTLS
import OSLog
import NimbleExtensions

enum ODLocalServerTLS {
	private struct IdentitySettings {
		let id: String
		let hostname: String
	}

	private static let _fileManager = FileManager.default
	private static func _baseDirectory() throws -> URL {
		guard let applicationSupport = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first else {
			throw ODLocalServerTLSError.storageUnavailable
		}
		return applicationSupport
			.appendingPathComponent("Odysseus", isDirectory: true)
			.appendingPathComponent("ServerTLS", isDirectory: true)
	}

	private static var _settings: IdentitySettings? {
		guard
			let stored = UserDefaults.standard.dictionary(forKey: ODPrefs.localServerTLSIdentity),
			let id = stored["id"] as? String,
				UUID(uuidString: id) != nil,
			let hostname = stored["hostname"] as? String,
				_isValidHostname(hostname)
		else {
			return nil
		}
		return IdentitySettings(id: id, hostname: hostname)
	}

	static var hostname: String? { _settings?.hostname }

	private static func _identityDirectory(for id: String, baseDirectory: URL) -> URL {
		baseDirectory.appendingPathComponent("identity-\(id)", isDirectory: true)
	}

	static func tlsConfiguration() throws -> TLSConfiguration {
		guard let settings = _settings else {
			throw ODLocalServerTLSError.identityNotConfigured
		}

		let baseDirectory = try _baseDirectory()
		let directory = _identityDirectory(for: settings.id, baseDirectory: baseDirectory)
		let certificateURL = directory.appendingPathComponent("server.crt")
		let privateKeyURL = directory.appendingPathComponent("server.pem")
		guard
			_fileManager.fileExists(atPath: certificateURL.path),
			_fileManager.fileExists(atPath: privateKeyURL.path)
		else {
			throw ODLocalServerTLSError.identityNotConfigured
		}

		try _protectStorage(at: directory, baseDirectory: baseDirectory, privateKeyURL: privateKeyURL)
		guard let certificateData = try? Data(contentsOf: certificateURL) else {
			throw ODLocalServerTLSError.invalidIdentity
		}
		try _validateServerCertificate(certificateData, hostname: settings.hostname)
		return try _makeTLSConfiguration(certificateURL: certificateURL, privateKeyURL: privateKeyURL)
	}

	static func installIdentity(
		certificateData: Data,
		privateKeyData: Data,
		hostname rawHostname: String
	) throws {
		let hostname = rawHostname.trimmingCharacters(in: .whitespacesAndNewlines)
		guard _isValidHostname(hostname) else {
			throw ODLocalServerTLSError.invalidHostname
		}

		guard !certificateData.isEmpty, !privateKeyData.isEmpty else {
			throw ODLocalServerTLSError.unreadableIdentity
		}

		let previousID = _settings?.id
		let newID = UUID().uuidString
		let baseDirectory = try _baseDirectory()
		let newDirectory = _identityDirectory(for: newID, baseDirectory: baseDirectory)
		do {
			try _fileManager.createDirectory(
				at: baseDirectory,
				withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700]
			)
			try _fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDirectory.path)
			var backupValues = URLResourceValues()
			backupValues.isExcludedFromBackup = true
			var backupDirectory = baseDirectory
			try backupDirectory.setResourceValues(backupValues)

			try _fileManager.createDirectory(
				at: newDirectory,
				withIntermediateDirectories: false,
				attributes: [.posixPermissions: 0o700]
			)
			let storedCertificate = newDirectory.appendingPathComponent("server.crt")
			let storedPrivateKey = newDirectory.appendingPathComponent("server.pem")
			try certificateData.write(to: storedCertificate, options: [.atomic, .completeFileProtection])
			try privateKeyData.write(to: storedPrivateKey, options: [.atomic, .completeFileProtection])
			try _protectStorage(at: newDirectory, baseDirectory: baseDirectory, privateKeyURL: storedPrivateKey)

			// Parse the chain and private key and ask OpenSSL to create a
			// server context before switching the active identity. This catches
			// malformed files and mismatched certificate/key pairs.
			_ = try _makeTLSConfiguration(certificateURL: storedCertificate, privateKeyURL: storedPrivateKey)
			try _validateServerCertificate(certificateData, hostname: hostname)

			UserDefaults.standard.set(
				["id": newID, "hostname": hostname],
				forKey: ODPrefs.localServerTLSIdentity
			)

			if let previousID, previousID != newID {
				do {
					try _fileManager.removeFileIfNeeded(at: _identityDirectory(for: previousID, baseDirectory: baseDirectory))
				} catch {
					Logger.misc.error("A replaced TLS identity could not be removed (error code \(error._code)).")
				}
			}
		} catch let error as ODLocalServerTLSError {
			_removeFailedIdentity(at: newDirectory)
			throw error
		} catch {
			_removeFailedIdentity(at: newDirectory)
			throw ODLocalServerTLSError.invalidIdentity
		}
	}

	static func removeIdentity() throws {
		if let previousID = _settings?.id {
			let baseDirectory = try _baseDirectory()
			try _fileManager.removeFileIfNeeded(at: _identityDirectory(for: previousID, baseDirectory: baseDirectory))
		}
		UserDefaults.standard.removeObject(forKey: ODPrefs.localServerTLSIdentity)
	}

	/// Remove the legacy files written by the old downloader. They were
	/// placed in Documents (which is user-accessible) and must never be
	/// reused as a silent fallback.
	static func removeLegacySharedMaterial() {
		let documents = URL.documentsDirectory
		for name in ["server.pem", "server.crt", "commonName.txt"] {
			do {
				try _fileManager.removeFileIfNeeded(at: documents.appendingPathComponent(name))
			} catch {
				Logger.misc.error("Could not remove legacy local-server TLS material (error code \(error._code)).")
			}
		}
	}

	private static func _removeFailedIdentity(at directory: URL) {
		guard _fileManager.fileExists(atPath: directory.path) else { return }
		do {
			try _fileManager.removeItem(at: directory)
		} catch {
			Logger.misc.error("Could not remove failed TLS identity material (error code \(error._code)).")
		}
	}

	private static func _validateServerCertificate(_ pemData: Data, hostname: String) throws {
		guard let pem = String(data: pemData, encoding: .utf8) else {
			throw ODLocalServerTLSError.invalidIdentity
		}

		let beginMarker = "-----BEGIN CERTIFICATE-----"
		let endMarker = "-----END CERTIFICATE-----"
		var remaining = pem
		var derCertificates: [Data] = []
		while let begin = remaining.range(of: beginMarker) {
			guard
				String(remaining[..<begin.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
				let end = remaining.range(of: endMarker, range: begin.upperBound..<remaining.endIndex)
			else {
				throw ODLocalServerTLSError.invalidIdentity
			}
			let base64 = remaining[begin.upperBound..<end.lowerBound]
				.filter { !$0.isWhitespace }
			guard let der = Data(base64Encoded: String(base64)) else {
				throw ODLocalServerTLSError.invalidIdentity
			}
			derCertificates.append(der)
			remaining = String(remaining[end.upperBound...])
		}
		guard
			!derCertificates.isEmpty,
			remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else {
			throw ODLocalServerTLSError.invalidIdentity
		}

		let certificates = try derCertificates.map { der -> SecCertificate in
			guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
				throw ODLocalServerTLSError.invalidIdentity
			}
			return certificate
		}
		let policy = SecPolicyCreateSSL(true, hostname as CFString)
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess, let trust else {
			throw ODLocalServerTLSError.untrustedOrWrongHostname
		}
		guard SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
			SecTrustEvaluateWithError(trust, nil) else {
			throw ODLocalServerTLSError.untrustedOrWrongHostname
		}
	}

	private static func _protectStorage(at directory: URL, baseDirectory: URL, privateKeyURL: URL) throws {
		try _fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDirectory.path)
		try _fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
		try _fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKeyURL.path)
		var values = URLResourceValues()
		values.isExcludedFromBackup = true
		var protectedBaseDirectory = baseDirectory
		try protectedBaseDirectory.setResourceValues(values)
	}

	private static func _makeTLSConfiguration(
		certificateURL: URL,
		privateKeyURL: URL
	) throws -> TLSConfiguration {
		let certificateChain = try NIOSSLCertificate.fromPEMFile(certificateURL.path).map {
			NIOSSLCertificateSource.certificate($0)
		}
		guard !certificateChain.isEmpty else {
			throw ODLocalServerTLSError.invalidIdentity
		}

		let privateKey = try NIOSSLPrivateKey(file: privateKeyURL.path, format: .pem)
		let configuration = TLSConfiguration.makeServerConfiguration(
			certificateChain: certificateChain,
			privateKey: .privateKey(privateKey)
		)
		_ = try NIOSSLContext(configuration: configuration)
		return configuration
	}

	private static func _isValidHostname(_ hostname: String) -> Bool {
		guard
			!hostname.isEmpty,
			hostname.utf8.count <= 253,
			!hostname.hasPrefix("."),
			!hostname.hasSuffix("."),
			hostname.unicodeScalars.allSatisfy({
				CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0)
			})
		else {
			return false
		}

		let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
		return labels.allSatisfy { label in
			label.utf8.count <= 63
				&& !label.isEmpty
				&& !label.hasPrefix("-")
				&& !label.hasSuffix("-")
		}
	}
}

enum ODLocalServerTLSError: LocalizedError {
	case storageUnavailable
	case identityNotConfigured
	case invalidHostname
	case unreadableIdentity
	case invalidIdentity
	case untrustedOrWrongHostname

	var errorDescription: String? {
		switch self {
		case .storageUnavailable:
			return .localized("Odysseus couldn't access protected Application Support storage for the TLS identity.")
		case .identityNotConfigured:
			return .localized("A user-owned TLS certificate and private key are required for Fully Local installation. Import them in Settings → Installation → Server.")
		case .invalidHostname:
			return .localized("Enter a valid hostname covered by the imported certificate.")
		case .unreadableIdentity:
			return .localized("The selected certificate or private-key file could not be read.")
		case .invalidIdentity:
			return .localized("The selected TLS certificate and private key are invalid or do not match.")
		case .untrustedOrWrongHostname:
			return .localized("The certificate is not currently trusted for this hostname, is expired, or is not valid for server TLS.")
		}
	}
}
