import XCTest
@testable import Feather

@MainActor
final class ODAppleIDMaterialCleanupTests: XCTestCase {
	func testCleanupRemovesOnlyOldAppOwnedSigningDirectories() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("OdysseusAppleIDCleanupTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let now = Date(timeIntervalSince1970: 2_000_000_000)
		let stale = root.appendingPathComponent("OdysseusAppleID_\(UUID().uuidString)", isDirectory: true)
		let recent = root.appendingPathComponent("OdysseusAppleID_\(UUID().uuidString)", isDirectory: true)
		let unrelated = root.appendingPathComponent("OtherSigningMaterial_\(UUID().uuidString)", isDirectory: true)
		for directory in [stale, recent, unrelated] {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try Data("test material".utf8).write(to: directory.appendingPathComponent("appleid.p12"))
		}
		try FileManager.default.setAttributes(
			[.modificationDate: now.addingTimeInterval(-25 * 60 * 60)],
			ofItemAtPath: stale.path
		)
		try FileManager.default.setAttributes(
			[.modificationDate: now.addingTimeInterval(-60 * 60)],
			ofItemAtPath: recent.path
		)
		try FileManager.default.setAttributes(
			[.modificationDate: now.addingTimeInterval(-25 * 60 * 60)],
			ofItemAtPath: unrelated.path
		)

		ODAppleIDManager.cleanupStaleSigningMaterial(in: root, olderThan: 24 * 60 * 60, now: now)

		XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
		XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
		XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
	}
}
