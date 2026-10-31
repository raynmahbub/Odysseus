import XCTest
@testable import Feather

final class ODZsignOutcomeTests: XCTestCase {
	func testAcceptsOnlySuccessfulReturnAndCallback() throws {
		XCTAssertNoThrow(try ODZsignOutcome.validate(returned: true, callbackSuccess: true, callbackError: nil))
	}

	func testRejectsFalseZsignReturnEvenWhenCallbackClaimsSuccess() {
		XCTAssertThrowsError(try ODZsignOutcome.validate(returned: false, callbackSuccess: true, callbackError: nil))
	}

	func testRejectsCallbackFailureEvenWhenReturnIsSuccessful() {
		XCTAssertThrowsError(try ODZsignOutcome.validate(returned: true, callbackSuccess: false, callbackError: nil))
	}

	func testPropagatesCallbackError() {
		let callbackError = NSError(domain: "ZsignTest", code: 42)
		XCTAssertThrowsError(try ODZsignOutcome.validate(returned: true, callbackSuccess: true, callbackError: callbackError)) { error in
			XCTAssertEqual((error as NSError).code, 42)
		}
	}

	func testRejectsMissingCallback() {
		XCTAssertThrowsError(try ODZsignOutcome.validate(returned: true, callbackSuccess: nil, callbackError: nil))
	}
}
