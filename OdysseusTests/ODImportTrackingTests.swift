import XCTest
@testable import Feather

/// Regression coverage for ODY-BUG-004: an import that finishes after the
/// three-second post-download window must still be signed, not discarded.
final class ODImportTrackingTests: XCTestCase {
	func testImportWhileTheDownloadIsActiveIsSigned() {
		var tracking = ODImportTracking()
		tracking.begin("app-1")

		XCTAssertEqual(tracking.imported("app-1"), .signing)
	}

	func testLateImportAfterTheDownloadEndedIsStillSigned() {
		var tracking = ODImportTracking()
		tracking.begin("app-2")

		XCTAssertTrue(tracking.downloadStopped("app-2"))
		XCTAssertEqual(tracking.imported("app-2"), .signing, "a slow import was discarded")
	}

	func testImportForAnUnknownIdIsIgnored() {
		var tracking = ODImportTracking()

		XCTAssertEqual(tracking.imported("never-requested"), .ignored)
	}

	func testFailedDownloadCannotBeSignedByALaterImport() {
		var tracking = ODImportTracking()
		tracking.begin("app-3")
		tracking.forget("app-3")

		XCTAssertEqual(tracking.imported("app-3"), .ignored)
	}

	func testDownloadStoppedOnlyReportsTheFirstTime() {
		var tracking = ODImportTracking()
		tracking.begin("app-4")

		XCTAssertTrue(tracking.downloadStopped("app-4"))
		XCTAssertFalse(tracking.downloadStopped("app-4"))
	}

	func testImportIsConsumedOnce() {
		var tracking = ODImportTracking()
		tracking.begin("app-5")

		XCTAssertEqual(tracking.imported("app-5"), .signing)
		XCTAssertEqual(tracking.imported("app-5"), .ignored)
	}

	func testTrackedIdsStayQueryableWhileActive() {
		var tracking = ODImportTracking()
		tracking.begin("app-6")

		XCTAssertTrue(tracking.isTracking("app-6"))
		XCTAssertTrue(tracking.isTrackingAnything)

		tracking.downloadStopped("app-6")

		XCTAssertTrue(tracking.isTracking("app-6"), "recoverable ids must still be tracked")
		XCTAssertFalse(tracking.isTrackingAnything)
	}

	func testRecoveryWindowIsBounded() {
		var tracking = ODImportTracking()
		let overflow = ODImportTracking.recoverableLimit + 5

		for index in 0..<overflow {
			let id = "app-\(index)"
			tracking.begin(id)
			tracking.downloadStopped(id)
		}

		// The oldest entries fall out; the most recent ones remain signable.
		XCTAssertEqual(tracking.imported("app-0"), .ignored)
		XCTAssertEqual(tracking.imported("app-\(overflow - 1)"), .signing)
	}
}
