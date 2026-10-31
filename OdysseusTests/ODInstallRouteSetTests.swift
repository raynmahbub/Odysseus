import XCTest
@testable import Feather

/// Coverage for S-04: the local install server lives on all interfaces, so its
/// routes must not be guessable by another host on the network.
final class ODInstallRouteSetTests: XCTestCase {
	private let identifier = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

	private func makeRoutes(secret: String = "0123456789abcdef") -> ODInstallRouteSet {
		ODInstallRouteSet(secret: secret, id: identifier)
	}

	func testEveryPathCarriesTheSecret() {
		let routes = makeRoutes()

		for path in [
			routes.plistPath,
			routes.payloadPath,
			routes.smallImagePath,
			routes.largeImagePath,
			routes.installPath,
		] {
			XCTAssertTrue(path.hasPrefix("/\(routes.secret)/"), "path is not scoped to the install secret: \(path)")
		}
	}

	func testPathsAreDistinctAndStable() {
		let routes = makeRoutes()

		XCTAssertEqual(routes.plistPath, "/0123456789abcdef/11111111-2222-3333-4444-555555555555.plist")
		XCTAssertEqual(routes.payloadPath, "/0123456789abcdef/11111111-2222-3333-4444-555555555555.ipa")

		let all = [routes.plistPath, routes.payloadPath, routes.smallImagePath, routes.largeImagePath, routes.installPath]
		XCTAssertEqual(Set(all).count, all.count)
	}

	func testTwoInstallsDoNotShareRoutes() {
		let first = makeRoutes(secret: "aaaaaaaaaaaaaaaa")
		let second = makeRoutes(secret: "bbbbbbbbbbbbbbbb")

		XCTAssertNotEqual(first.plistPath, second.plistPath)
		XCTAssertNotEqual(first.payloadPath, second.payloadPath)
		XCTAssertFalse(second.plistPath.hasPrefix("/\(first.secret)/"))
	}

	func testPathWithoutTheSecretDoesNotMatch() {
		let routes = makeRoutes()

		XCTAssertNotEqual(routes.plistPath, "/app.plist")
		XCTAssertNotEqual(routes.installPath, "/install")
		XCTAssertNotEqual(routes.payloadPath, "/app.ipa")
	}

	func testGeneratedSecretsAreWellFormedAndUnique() {
		let secrets = (0..<16).map { _ in ODInstallRouteSet.makeSecret() }

		for secret in secrets {
			XCTAssertTrue(ODInstallRouteSet.isWellFormedSecret(secret), "bad secret: \(secret)")
			XCTAssertEqual(secret.count, 32)
		}
		XCTAssertEqual(Set(secrets).count, secrets.count, "secrets must not repeat")
	}

	func testWellFormedSecretRejectsWeakValues() {
		XCTAssertFalse(ODInstallRouteSet.isWellFormedSecret("abc"))
		XCTAssertFalse(ODInstallRouteSet.isWellFormedSecret(String(repeating: "z", count: 32)))
		XCTAssertFalse(ODInstallRouteSet.isWellFormedSecret(String(repeating: "a", count: 65)))
	}
}
