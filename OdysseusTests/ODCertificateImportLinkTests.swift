import Foundation
import XCTest
@testable import Feather

/// Coverage for the export → re-import round trip.
///
/// The exporter used to write the password raw while this app's importer
/// base64-decoded it, and never emitted a provisioning profile — so a link
/// Odysseus produced could not be imported by Odysseus.
final class ODCertificateImportLinkTests: XCTestCase {
	private let odysseusTemplate = "odysseus://import-certificate?p12=$(BASE64_CERT)&mobileprovision=$(BASE64_PROVISION)&password=$(BASE64_PASSWORD)"
	private let legacyTemplate = "odysseus://import-certificate?p12=$(BASE64_CERT)&mobileprovision=$(BASE64_PROVISION)&password=$(PASSWORD)"

	private let p12 = Data([0x30, 0x82, 0x01, 0x0A, 0x02, 0x01, 0x03, 0xFB, 0xFF])
	private let profile = Data("<?xml version=\"1.0\"?><plist><dict/></plist>".utf8)

	private func makeURL(_ query: String) throws -> URL {
		try XCTUnwrap(URL(string: "odysseus://import-certificate?\(query)"))
	}

	// MARK: - Round trip

	func testExportedLinkImportsBackIntoOdysseus() throws {
		let url = try XCTUnwrap(
			ODCertificateExport.makeURL(
				template: odysseusTemplate,
				certificateBase64: p12.base64EncodedString(),
				password: "p@ss&word%",
				provisionBase64: profile.base64EncodedString()
			)
		)

		let fields = try ODCertificateImportLink.parse(url)

		XCTAssertEqual(fields.p12Data, p12)
		XCTAssertEqual(fields.provisionData, profile)
		XCTAssertEqual(fields.passwordCandidates.first, "p@ss&word%")
	}

	func testPasswordWithReservedCharactersSurvivesTheRoundTrip() throws {
		for password in ["a+b", "50%off", "p#1?", "has space", "plain"] {
			let url = try XCTUnwrap(
				ODCertificateExport.makeURL(
					template: odysseusTemplate,
					certificateBase64: p12.base64EncodedString(),
					password: password,
					provisionBase64: profile.base64EncodedString()
				)
			)

			let fields = try ODCertificateImportLink.parse(url)
			XCTAssertEqual(fields.passwordCandidates, [password], "password did not survive: \(password)")
		}
	}

	func testLegacyRawPasswordTemplateIsAccepted() throws {
		let url = try XCTUnwrap(
			ODCertificateExport.makeURL(
				template: legacyTemplate,
				certificateBase64: p12.base64EncodedString(),
				password: "p@ss&word",
				provisionBase64: profile.base64EncodedString()
			)
		)

		let fields = try ODCertificateImportLink.parse(url)
		XCTAssertEqual(fields.p12Data, p12)
		XCTAssertEqual(fields.passwordCandidates, ["p@ss&word"])
	}

	// MARK: - Password candidates

	func testUndeclaredBase64PasswordIsTriedFirstAndRawSecond() {
		let encoded = Data("secret".utf8).base64EncodedString()
		XCTAssertEqual(
			ODCertificateImportLink.passwordCandidates(from: encoded, declaredEncoding: nil),
			["secret", encoded]
		)
	}

	func testDeclaredRawEncodingIsNotDecoded() {
		XCTAssertEqual(
			ODCertificateImportLink.passwordCandidates(from: "c2VjcmV0", declaredEncoding: "raw"),
			["c2VjcmV0"]
		)
	}

	func testDeclaredBase64EncodingIsDecoded() {
		XCTAssertEqual(
			ODCertificateImportLink.passwordCandidates(from: "c2VjcmV0", declaredEncoding: "base64"),
			["secret"]
		)
	}

	func testPlainPasswordIsUsedVerbatim() {
		XCTAssertEqual(
			ODCertificateImportLink.passwordCandidates(from: "p@ss&word", declaredEncoding: nil),
			["p@ss&word"]
		)
	}

	func testMissingPasswordYieldsNoCandidates() {
		XCTAssertEqual(ODCertificateImportLink.passwordCandidates(from: nil, declaredEncoding: nil), [])
	}

	func testPasswordEncodingParameterIsHonoured() throws {
		let url = try makeURL("p12=\(p12.base64EncodedString())&mobileprovision=\(profile.base64EncodedString())&password=c2VjcmV0&password_encoding=base64")
		let fields = try ODCertificateImportLink.parse(url)
		XCTAssertEqual(fields.passwordCandidates, ["secret"])
	}

	// MARK: - Malformed input

	func testMissingCertificateIsRejected() throws {
		let url = try makeURL("mobileprovision=\(profile.base64EncodedString())&password=x")
		XCTAssertThrowsError(try ODCertificateImportLink.parse(url)) { error in
			XCTAssertEqual(error as? ODCertificateImportError, .missingField("p12"))
		}
	}

	func testMissingProfileIsRejected() throws {
		let url = try makeURL("p12=\(p12.base64EncodedString())&password=x")
		XCTAssertThrowsError(try ODCertificateImportLink.parse(url)) { error in
			XCTAssertEqual(error as? ODCertificateImportError, .missingField("mobileprovision"))
		}
	}

	func testMissingPasswordIsRejected() throws {
		let url = try makeURL("p12=\(p12.base64EncodedString())&mobileprovision=\(profile.base64EncodedString())")
		XCTAssertThrowsError(try ODCertificateImportLink.parse(url)) { error in
			XCTAssertEqual(error as? ODCertificateImportError, .missingField("password"))
		}
	}

	func testInvalidBase64IsRejected() throws {
		let url = try makeURL("p12=not*base64*at*all&mobileprovision=\(profile.base64EncodedString())&password=x")
		XCTAssertThrowsError(try ODCertificateImportLink.parse(url)) { error in
			XCTAssertEqual(error as? ODCertificateImportError, .invalidBase64("p12"))
		}
	}

	func testOversizedCertificateIsRejectedBeforeDecoding() throws {
		let oversized = Data(repeating: 0x41, count: ODCertificateImportLink.maximumP12Bytes + 1).base64EncodedString()
		let url = try makeURL("p12=\(oversized)&mobileprovision=\(profile.base64EncodedString())&password=x")
		XCTAssertThrowsError(try ODCertificateImportLink.parse(url)) { error in
			XCTAssertEqual(error as? ODCertificateImportError, .tooLarge("p12"))
		}
	}

	func testForeignSchemeIsRejected() throws {
		let url = try XCTUnwrap(URL(string: "https://example.com/import-certificate?p12=x"))
		XCTAssertThrowsError(try ODCertificateImportLink.parse(url)) { error in
			XCTAssertEqual(error as? ODCertificateImportError, .unsupportedLink)
		}
	}

	func testForeignHostIsRejected() throws {
		let url = try XCTUnwrap(URL(string: "odysseus://export-certificate?p12=x"))
		XCTAssertThrowsError(try ODCertificateImportLink.parse(url)) { error in
			XCTAssertEqual(error as? ODCertificateImportError, .unsupportedLink)
		}
	}

	func testDoubleEncodedPayloadIsStillReadable() throws {
		// Older producers percent-encoded a value that was already
		// percent-encoded; `URLComponents` only undoes the outer layer.
		let data = Data([0xFF, 0xFB, 0x00, 0x2F])
		let once = data.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
		let twice = once.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
		XCTAssertTrue(twice.contains("%25"), "expected the payload to be encoded twice")

		let url = try makeURL("p12=\(twice)&mobileprovision=\(profile.base64EncodedString())&password=x")

		let fields = try ODCertificateImportLink.parse(url)
		XCTAssertEqual(fields.p12Data, data)
	}

	func testErrorMessagesNeverContainTheLinkContents() throws {
		// `*` is not in the base64 alphabet, so the certificate field is
		// rejected. The message must name the field, never echo the value:
		// these fields carry key material and a password.
		let url = try makeURL("p12=*not*base64*&mobileprovision=\(profile.base64EncodedString())&password=super-secret-password")
		do {
			_ = try ODCertificateImportLink.parse(url)
			XCTFail("expected the import link to be rejected")
		} catch {
			let message = error.localizedDescription
			XCTAssertFalse(message.contains("super-secret-password"))
			XCTAssertFalse(message.contains("not*base64"))
		}
	}
}
