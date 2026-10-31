//
//  ODOCSPChecker.swift
//  Odysseus
//
//  Real OCSP revocation checks against Apple's responder.
//
//  1. Read the signing certificate (leaf) from the .p12 (or the
//     provisioning profile as a fallback).
//  2. Find its issuer: the bundled Apple WWDR intermediates, or the
//     caIssuers URL in the certificate.
//  3. POST an OCSP request (SHA-1 CertID) to the responder named in the
//     certificate (ocsp.apple.com).
//  4. Read the answer: good / revoked (date + reason), validate the
//     responder ID, signature, and Apple OCSP-signing trust.
//
//  Unlike the old one-way `revoked` flag, every check can move a
//  certificate in either direction.
//

import Foundation
import Security
import CryptoKit
import OSLog
import NimbleExtensions

// MARK: - Result
struct ODOCSPResult: Codable, Equatable {
	enum Status: String, Codable {
		case valid
		case revoked
		case unknown
		case couldntCheck
	}

	var status: Status
	var revokedAt: Date?
	var reason: Int?
	var checkedAt: Date
	var producedAt: Date?
	var thisUpdate: Date?
	var nextUpdate: Date?
	/// The responder's signature, identity, and Apple OCSP-signing trust passed.
	var signatureVerified: Bool
	var responderURL: String?
	var detail: String?

	var reasonName: String? { ODOCSPCore.reasonName(reason) }

	/// Only signed, determinate OCSP answers within their response validity
	/// window are reusable for signing decisions.
	func isFresh(at now: Date = Date(), maximumAge: TimeInterval = 3600) -> Bool {
		guard
			(status == .valid || status == .revoked),
			signatureVerified,
			maximumAge > 0,
			checkedAt <= now.addingTimeInterval(300),
			now.timeIntervalSince(checkedAt) <= maximumAge,
			let producedAt,
			producedAt <= now.addingTimeInterval(300),
			now.timeIntervalSince(producedAt) <= maximumAge,
			let thisUpdate,
			thisUpdate <= now.addingTimeInterval(300),
			now.timeIntervalSince(thisUpdate) <= maximumAge,
			thisUpdate <= producedAt.addingTimeInterval(300)
		else {
			return false
		}
		if let nextUpdate,
			now > nextUpdate.addingTimeInterval(300) || nextUpdate < thisUpdate.addingTimeInterval(-300)
		{
			return false
		}
		return true
	}

	var title: String {
		switch status {
		case .valid: return .localized("Valid")
		case .revoked: return .localized("Revoked")
		case .unknown: return .localized("Unknown")
		case .couldntCheck: return .localized("Couldn't check")
		}
	}

	var icon: String {
		switch status {
		case .valid: return "checkmark.seal.fill"
		case .revoked: return "xmark.octagon.fill"
		case .unknown: return "questionmark.circle.fill"
		case .couldntCheck: return "exclamationmark.triangle.fill"
		}
	}

	static func couldntCheck(_ detail: String, url: String? = nil) -> ODOCSPResult {
		ODOCSPResult(status: .couldntCheck, revokedAt: nil, reason: nil, checkedAt: Date(), producedAt: nil, thisUpdate: nil, nextUpdate: nil, signatureVerified: false, responderURL: url, detail: detail)
	}
}

// MARK: - Checker
enum ODOCSPChecker {
	private static let _issuerCache = NSCache<NSData, NSData>()

	static func check(certificateDER: Data) async -> ODOCSPResult {
		let leaf: ODX509
		do {
			leaf = try ODX509(der: certificateDER)
		} catch {
			return .couldntCheck(.localized("The certificate could not be read."))
		}

		let issuer = await _issuer(for: leaf)

		guard let issuerKeyHash = issuer?.keyHash ?? leaf.authorityKeyID else {
			return .couldntCheck(.localized("The issuing Apple certificate wasn't found."))
		}

		let certID = ODOCSPCore.certID(
			issuerNameHash: leaf.issuerNameHash,
			issuerKeyHash: issuerKeyHash,
			serial: leaf.serial
		)
		let requestBody = ODOCSPCore.request(certID: certID)

		var lastError = String.localized("No OCSP responder is listed in the certificate.")
		for url in _responderURLs(for: leaf, issuer: issuer) {
			do {
				var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
				request.httpMethod = "POST"
				request.setValue("application/ocsp-request", forHTTPHeaderField: "Content-Type")
				request.setValue("application/ocsp-response", forHTTPHeaderField: "Accept")
				request.httpBody = requestBody

				let (data, response) = try await URLSession.shared.data(for: request)
				guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
					lastError = .localized("The OCSP responder returned an error.")
					continue
				}

				let parsed = try ODOCSPCore.parse(
					response: data,
					serial: leaf.serial,
					issuerNameHash: leaf.issuerNameHash,
					issuerKeyHash: issuerKeyHash
				)
				guard parsed.responseStatus == 0 else {
					lastError = ODOCSPCore.responseStatusName(parsed.responseStatus)
					continue
				}

				let verification = _verifySignature(parsed, issuer: issuer)
				guard verification == .verified else {
					lastError = verification == .invalid
						? .localized("The OCSP response signature is not valid.")
						: .localized("The OCSP response signature or responder identity could not be verified.")
					continue
				}

				var result = ODOCSPResult(
					status: .unknown,
					revokedAt: nil,
					reason: nil,
					checkedAt: Date(),
					producedAt: parsed.producedAt,
					thisUpdate: parsed.thisUpdate,
					nextUpdate: parsed.nextUpdate,
					signatureVerified: true,
					responderURL: url.absoluteString,
					detail: nil
				)

				switch parsed.certStatus {
				case .good:
					result.status = .valid
				case .revoked(let date, let reason):
					result.status = .revoked
					result.revokedAt = date
					result.reason = reason
				case .unknown:
					result.status = .unknown
					result.detail = .localized("Apple's responder doesn't know this certificate.")
				case .none:
					result.status = .unknown
					result.detail = .localized("The certificate wasn't in Apple's answer.")
				}

				return result
			} catch {
				lastError = error.localizedDescription
			}
		}

		return .couldntCheck(lastError)
	}

	// MARK: Responder
	private static func _responderURLs(for leaf: ODX509, issuer: ODX509?) -> [URL] {
		var urls = leaf.ocspURLs
		if urls.isEmpty {
			// Same fallbacks zsign uses.
			let issuerName = issuer?.commonName ?? ""
			let ou = issuer.flatMap { _organizationalUnit(of: $0) } ?? ""
			let path: String
			if issuerName.contains("G6") || ou == "G6" { path = "ocsp03-wwdrg6" }
			else if issuerName.contains("G3") || ou == "G3" { path = "ocsp03-wwdrg3" }
			else if issuerName.contains("G2") || ou == "G2" { path = "ocsp03-wwdrg2" }
			else if ou == "G4" { path = "ocsp03-wwdrg4" }
			else if ou == "G5" { path = "ocsp03-wwdrg5" }
			else { path = "ocsp03-wwdr01" }
			if let url = URL(string: "http://ocsp.apple.com/\(path)") {
				urls.append(url)
			}
		}
		return urls
	}

	private static func _organizationalUnit(of cert: ODX509) -> String? {
		guard let secCert = SecCertificateCreateWithData(nil, cert.der as CFData),
			  let summary = SecCertificateCopySubjectSummary(secCert) as String? else {
			return nil
		}
		for gen in ["G2", "G3", "G4", "G5", "G6", "G7", "G8"] where summary.contains(gen) {
			return gen
		}
		return nil
	}

	// MARK: Issuer
	static var bundledIntermediates: [ODX509] = {
		let names = ["AppleWWDRCA", "AppleWWDRCAG2", "AppleWWDRCAG3", "AppleWWDRCAG4", "AppleWWDRCAG5", "AppleWWDRCAG6"]
		return names.compactMap { name in
			let url = Bundle.main.url(forResource: name, withExtension: "cer")
				?? Bundle.main.url(forResource: name, withExtension: "cer", subdirectory: "WWDR")
			guard let url, let data = try? Data(contentsOf: url) else { return nil }
			return try? ODX509(der: data)
		}
	}()

	private static func _issuer(for leaf: ODX509) async -> ODX509? {
		let candidates = bundledIntermediates.filter { $0.subjectNameDER == leaf.issuerNameDER }
		if let aki = leaf.authorityKeyID, let match = candidates.first(where: { $0.subjectKeyID == aki || $0.keyHash == aki }) {
			return match
		}
		if candidates.count == 1 {
			return candidates.first
		}

		for url in leaf.caIssuerURLs {
			if let cached = _issuerCache.object(forKey: url.absoluteString.data(using: .utf8)! as NSData) {
				return try? ODX509(der: cached as Data)
			}
			guard let (data, _) = try? await URLSession.shared.data(from: url),
				  let cert = try? ODX509(der: data),
				  cert.subjectNameDER == leaf.issuerNameDER
			else { continue }
			_issuerCache.setObject(data as NSData, forKey: url.absoluteString.data(using: .utf8)! as NSData)
			return cert
		}

		return candidates.first
	}

	// MARK: Signature
	private enum Verification: Equatable {
		case verified
		case unverifiable
		case invalid
	}

	private static func _verifySignature(_ response: ODOCSPParsedResponse, issuer: ODX509?) -> Verification {
		guard
			let issuer,
			let responderID = response.responderID,
			let tbs = response.tbsResponseData,
			let signature = response.signature,
			let algorithmOID = response.signatureAlgorithmOID,
			let algorithm = _secAlgorithm(algorithmOID),
			let producedAt = response.producedAt
		else {
			return .unverifiable
		}

		var signers = response.certificates.compactMap { try? ODX509(der: $0) }
		if _matches(responderID, certificate: issuer), !signers.contains(where: { $0.der == issuer.der }) {
			signers.append(issuer)
		}
		signers = signers.filter { _matches(responderID, certificate: $0) }
		guard !signers.isEmpty else { return .unverifiable }

		var signatureWasValid = false
		for signer in signers {
			guard
				let signerCertificate = SecCertificateCreateWithData(nil, signer.der as CFData),
				let key = SecCertificateCopyKey(signerCertificate)
			else {
				continue
			}

			var error: Unmanaged<CFError>?
			guard SecKeyVerifySignature(key, algorithm, tbs as CFData, signature as CFData, &error) else {
				continue
			}
			signatureWasValid = true

			guard _isAuthorizedResponder(signer, issuer: issuer, producedAt: producedAt) else {
				continue
			}
			return .verified
		}

		return signatureWasValid ? .unverifiable : .invalid
	}

	private static func _matches(_ responderID: ODOCSPResponderID, certificate: ODX509) -> Bool {
		switch responderID {
		case .byName(let name):
			return certificate.subjectNameDER == name
		case .byKey(let keyHash):
			return certificate.keyHash == keyHash
		}
	}

	private static func _isAuthorizedResponder(_ signer: ODX509, issuer: ODX509, producedAt: Date) -> Bool {
		guard let issuerCertificate = SecCertificateCreateWithData(nil, issuer.der as CFData) else { return false }
		if signer.der == issuer.der {
			return _isAppleTrusted(
				[issuerCertificate],
				policy: SecPolicyCreateBasicX509(),
				at: producedAt
			)
		}

		guard
			signer.issuerNameDER == issuer.subjectNameDER,
			let signerCertificate = SecCertificateCreateWithData(nil, signer.der as CFData)
		else {
			return false
		}
		return _isAppleTrusted(
			[signerCertificate, issuerCertificate],
			policy: SecPolicyCreateOCSPSigner(),
			at: producedAt
		)
	}

	private static func _isAppleTrusted(_ certificates: [SecCertificate], policy: SecPolicy, at date: Date) -> Bool {
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess, let trust else {
			return false
		}
		guard
			SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
			SecTrustSetVerifyDate(trust, date as CFDate) == errSecSuccess,
			SecTrustEvaluateWithError(trust, nil)
		else { return false }

		guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
			  let root = chain.last,
			  let summary = SecCertificateCopySubjectSummary(root) as String? else {
			return false
		}
		return summary.localizedCaseInsensitiveContains("Apple")
	}

	private static func _secAlgorithm(_ oid: String) -> SecKeyAlgorithm? {
		switch oid {
		case "1.2.840.113549.1.1.5": return .rsaSignatureMessagePKCS1v15SHA1
		case "1.2.840.113549.1.1.11": return .rsaSignatureMessagePKCS1v15SHA256
		case "1.2.840.113549.1.1.12": return .rsaSignatureMessagePKCS1v15SHA384
		case "1.2.840.113549.1.1.13": return .rsaSignatureMessagePKCS1v15SHA512
		case "1.2.840.10045.4.3.2": return .ecdsaSignatureMessageX962SHA256
		case "1.2.840.10045.4.3.3": return .ecdsaSignatureMessageX962SHA384
		case "1.2.840.10045.4.3.4": return .ecdsaSignatureMessageX962SHA512
		default: return nil
		}
	}
}
