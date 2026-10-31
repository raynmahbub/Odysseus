import XCTest
@testable import Feather

final class ODOCSPResponderAuthorizationTests: XCTestCase {
	private let ocspSigningOID = "1.3.6.1.5.5.7.3.9"

	func testRequiresOCSPSigningExtendedKeyUsage() {
		XCTAssertFalse(
			ODX509.permitsOCSPSigning(
				extendedKeyUsageOIDs: ["1.3.6.1.5.5.7.3.1"],
				keyUsageBits: Data([0x80])
			)
		)
	}

	func testPresentKeyUsageMustAllowDigitalSignature() {
		XCTAssertTrue(
			ODX509.permitsOCSPSigning(
				extendedKeyUsageOIDs: [ocspSigningOID],
				keyUsageBits: Data([0x80])
			)
		)
		XCTAssertFalse(
			ODX509.permitsOCSPSigning(
				extendedKeyUsageOIDs: [ocspSigningOID],
				keyUsageBits: Data([0x40])
			)
		)
	}

	func testMissingKeyUsageDoesNotOverrideRequiredExtendedKeyUsage() {
		XCTAssertTrue(
			ODX509.permitsOCSPSigning(
				extendedKeyUsageOIDs: [ocspSigningOID],
				keyUsageBits: nil
			)
		)
	}
}
