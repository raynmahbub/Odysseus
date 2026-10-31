import Foundation
import XCTest
@testable import Feather

/// Regression coverage for ODY-BUG-001 / S-01: the certificate export used to
/// substitute the `.p12` password into a URL without escaping it.
final class ODCertificateExportTests: XCTestCase {
	private let template = "odysseus://import-certificate?name=Test&p12=$(BASE64_CERT)&password=$(PASSWORD)"

	func testPasswordWithReservedCharactersRoundTrips() throws {
		let passwords = ["p@ss&word", "a+b", "50%off", "has space", "p#1?", "plain"]

		for password in passwords {
			let url = try XCTUnwrap(
				ODCertificateExport.makeURL(
					template: template,
					certificateBase64: "Y2VydA==",
					password: password
				),
				"URL was not built for \(password)"
			)

			let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
			let items = try XCTUnwrap(components.queryItems)
			let recovered = items.first { $0.name == "password" }?.value

			XCTAssertEqual(recovered, password, "password did not survive the round trip")
		}
	}

	func testCertificateBlobRoundTrips() throws {
		let certificate = Data([0x00, 0xFF, 0x2B, 0x2F, 0x3D, 0x10]).base64EncodedString()

		let url = try XCTUnwrap(
			ODCertificateExport.makeURL(template: template, certificateBase64: certificate, password: "x")
		)
		let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
		let recovered = components.queryItems?.first { $0.name == "p12" }?.value

		XCTAssertEqual(recovered, certificate)
	}

	func testRawPasswordNeverAppearsInTheURL() throws {
		let url = try XCTUnwrap(
			ODCertificateExport.makeURL(
				template: template,
				certificateBase64: "Y2VydA==",
				password: "p@ss&word"
			)
		)

		XCTAssertFalse(url.absoluteString.contains("p@ss&word"))
		XCTAssertTrue(url.absoluteString.contains("p%40ss%26word"))
	}

	func testTemplateWithoutPlaceholdersIsRejected() {
		XCTAssertNil(
			ODCertificateExport.makeURL(
				template: "odysseus://import-certificate",
				certificateBase64: "Y2VydA==",
				password: "x"
			)
		)
	}

	func testCertificateOnlyTemplateIsAccepted() throws {
		let url = try XCTUnwrap(
			ODCertificateExport.makeURL(
				template: "odysseus://import-certificate?p12=$(BASE64_CERT)",
				certificateBase64: "Y2VydA==",
				password: "unused"
			)
		)
		XCTAssertEqual(url.scheme, "odysseus")
	}

	func testOversizedURLIsRejected() {
		let hugeCertificate = String(repeating: "A", count: ODCertificateExport.maximumURLLength)

		XCTAssertNil(
			ODCertificateExport.makeURL(
				template: template,
				certificateBase64: hugeCertificate,
				password: "x"
			)
		)
	}

	func testEmptyPasswordStillProducesAURL() throws {
		let url = try XCTUnwrap(
			ODCertificateExport.makeURL(template: template, certificateBase64: "Y2VydA==", password: "")
		)
		XCTAssertEqual(url.scheme, "odysseus")
	}

	func testDestinationDescriptionNamesSchemeAndHost() throws {
		let url = try XCTUnwrap(URL(string: "livecontainer://certificate?cert=abc"))
		XCTAssertEqual(
			ODCertificateExport.destinationDescription(for: url),
			"livecontainer://certificate"
		)
	}

	func testDestinationDescriptionForHostlessURL() throws {
		let url = try XCTUnwrap(URL(string: "odysseus:install"))
		XCTAssertEqual(ODCertificateExport.destinationDescription(for: url), "odysseus://")
	}
}
