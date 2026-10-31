import XCTest
@testable import Feather

/// Coverage for the install server's exposure: which address it binds, which
/// requests it answers, and which paths exist at all.
final class ODInstallServerAccessTests: XCTestCase {
	private let identifier = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
	private let secret = "0123456789abcdef0123456789abcdef"

	// MARK: - Binding

	func testSemiLocalBindsTheAdvertisedLANAddress() {
		XCTAssertEqual(
			ODInstallServerAccess.bindHost(
				serverMethod: 1,
				usesLoopbackFix: false,
				localAddress: "192.168.1.5",
				tlsHostname: nil
			),
			"192.168.1.5"
		)
	}

	func testSemiLocalWithTheLoopbackFixBindsLoopback() {
		XCTAssertEqual(
			ODInstallServerAccess.bindHost(
				serverMethod: 1,
				usesLoopbackFix: true,
				localAddress: "192.168.1.5",
				tlsHostname: nil
			),
			"127.0.0.1"
		)
	}

	func testSemiLocalWithoutAnAddressBindsLoopback() {
		XCTAssertEqual(
			ODInstallServerAccess.bindHost(
				serverMethod: 1,
				usesLoopbackFix: false,
				localAddress: nil,
				tlsHostname: nil
			),
			"127.0.0.1"
		)
	}

	func testTLSIdentityWithAnAddressBindsThatAddress() {
		XCTAssertEqual(
			ODInstallServerAccess.bindHost(
				serverMethod: 0,
				usesLoopbackFix: false,
				localAddress: "192.168.1.5",
				tlsHostname: "10.0.0.7"
			),
			"10.0.0.7"
		)
	}

	func testTLSIdentityWithLocalhostBindsLoopback() {
		XCTAssertEqual(
			ODInstallServerAccess.bindHost(
				serverMethod: 0,
				usesLoopbackFix: false,
				localAddress: "192.168.1.5",
				tlsHostname: "localhost"
			),
			"127.0.0.1"
		)
	}

	func testTLSIdentityWithACustomNameKeepsEveryInterface() {
		// A DNS name cannot be bound. This is the documented residual case:
		// the listener stays on 0.0.0.0 and the route secret plus the request
		// guard are the controls.
		XCTAssertEqual(
			ODInstallServerAccess.bindHost(
				serverMethod: 0,
				usesLoopbackFix: false,
				localAddress: "192.168.1.5",
				tlsHostname: "odysseus.local"
			),
			"0.0.0.0"
		)
	}

	func testOnlyRealIPv4AddressesAreAcceptedAsBindHosts() {
		XCTAssertEqual(ODInstallServerAccess.ipv4("192.168.1.5"), "192.168.1.5")
		XCTAssertNil(ODInstallServerAccess.ipv4("300.1.1.1"))
		XCTAssertNil(ODInstallServerAccess.ipv4("192.168.1"))
		XCTAssertNil(ODInstallServerAccess.ipv4("192.168.1.5.6"))
		XCTAssertNil(ODInstallServerAccess.ipv4("example.com"))
		XCTAssertNil(ODInstallServerAccess.ipv4(""))
		XCTAssertNil(ODInstallServerAccess.ipv4(nil))
	}

	// MARK: - Request guard

	func testOnlyGetIsServed() {
		XCTAssertFalse(
			ODInstallServerAccess.isAcceptableRequest(
				method: "POST",
				hostHeader: "192.168.1.5:4000",
				expectedHost: "192.168.1.5"
			)
		)
	}

	func testMatchingHostIsServed() {
		XCTAssertTrue(
			ODInstallServerAccess.isAcceptableRequest(
				method: "GET",
				hostHeader: "192.168.1.5:4000",
				expectedHost: "192.168.1.5"
			)
		)
	}

	func testHostComparisonIsCaseInsensitive() {
		XCTAssertTrue(
			ODInstallServerAccess.isAcceptableRequest(
				method: "get",
				hostHeader: "Odysseus.Local:4000",
				expectedHost: "odysseus.local"
			)
		)
	}

	func testForeignHostIsRejected() {
		XCTAssertFalse(
			ODInstallServerAccess.isAcceptableRequest(
				method: "GET",
				hostHeader: "evil.example:4000",
				expectedHost: "192.168.1.5"
			)
		)
	}

	func testHostlessRequestIsStillServed() {
		// The 128-bit route secret is the credential; refusing hostless
		// requests would only risk breaking an install for no security gain.
		XCTAssertTrue(
			ODInstallServerAccess.isAcceptableRequest(
				method: "GET",
				hostHeader: nil,
				expectedHost: "192.168.1.5"
			)
		)
	}

	func testHostComponentStripsThePort() {
		XCTAssertEqual(ODInstallServerAccess.hostComponent(of: "192.168.1.5:4000"), "192.168.1.5")
		XCTAssertEqual(ODInstallServerAccess.hostComponent(of: "192.168.1.5"), "192.168.1.5")
		XCTAssertEqual(ODInstallServerAccess.hostComponent(of: "[::1]:4000"), "[::1]")
		XCTAssertEqual(ODInstallServerAccess.hostComponent(of: " LOCALHOST:80 "), "localhost")
	}

	// MARK: - Route scoping

	private func makeRoutes() -> ODInstallRouteSet {
		ODInstallRouteSet(secret: secret, id: identifier)
	}

	func testSecretScopedPathsResolve() {
		let routes = makeRoutes()

		XCTAssertEqual(routes.route(for: routes.plistPath), .manifest)
		XCTAssertEqual(routes.route(for: routes.payloadPath), .payload)
		XCTAssertEqual(routes.route(for: routes.smallImagePath), .smallIcon)
		XCTAssertEqual(routes.route(for: routes.largeImagePath), .largeIcon)
		XCTAssertEqual(routes.route(for: routes.installPath), .installPage)
	}

	func testPathsWithoutTheSecretDoNotResolve() {
		let routes = makeRoutes()

		XCTAssertNil(routes.route(for: "/install"))
		XCTAssertNil(routes.route(for: "/app.plist"))
		XCTAssertNil(routes.route(for: "/app.ipa"))
		XCTAssertNil(routes.route(for: "/\(identifier.uuidString).ipa"))
		XCTAssertNil(routes.route(for: "/deadbeef/\(identifier.uuidString).ipa"))
	}

	func testTraversalAndAbsolutePathsDoNotResolve() {
		let routes = makeRoutes()

		XCTAssertNil(routes.route(for: "/../\(secret)/\(identifier.uuidString).ipa"))
		XCTAssertNil(routes.route(for: routes.payloadPath + "/../../Documents"))
		XCTAssertNil(routes.route(for: "/"))
		XCTAssertNil(routes.route(for: ""))
	}
}
