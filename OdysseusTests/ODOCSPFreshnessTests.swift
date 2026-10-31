import XCTest
@testable import Feather

final class ODOCSPFreshnessTests: XCTestCase {
	func testFreshnessRequiresVerifiedDeterminateStatusAndResponseTimes() {
		let now = Date(timeIntervalSince1970: 2_000_000_000)

		XCTAssertTrue(result(now: now).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, verified: false).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, status: .unknown).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, status: .couldntCheck).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, checkedAt: now.addingTimeInterval(-3601)).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, producedAt: now.addingTimeInterval(-3601)).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, thisUpdate: now.addingTimeInterval(-3601)).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, thisUpdate: now.addingTimeInterval(301)).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, nextUpdate: now.addingTimeInterval(-301)).isFresh(at: now, maximumAge: 3600))
	}

	func testRevokedIsDeterminateButExpiredOrUnverifiedRevocationIsNotFresh() {
		let now = Date(timeIntervalSince1970: 2_000_000_000)
		XCTAssertTrue(result(now: now, status: .revoked).isFresh(at: now, maximumAge: 3600))
		XCTAssertFalse(result(now: now, status: .revoked, verified: false).isFresh(at: now, maximumAge: 3600))
	}

	private func result(
		now: Date,
		status: ODOCSPResult.Status = .valid,
		verified: Bool = true,
		checkedAt: Date? = nil,
		producedAt: Date? = nil,
		thisUpdate: Date? = nil,
		nextUpdate: Date? = nil
	) -> ODOCSPResult {
		ODOCSPResult(
			status: status,
			revokedAt: nil,
			reason: nil,
			checkedAt: checkedAt ?? now,
			producedAt: producedAt ?? now,
			thisUpdate: thisUpdate ?? now,
			nextUpdate: nextUpdate ?? now.addingTimeInterval(3600),
			signatureVerified: verified,
			responderURL: nil,
			detail: nil
		)
	}
}
