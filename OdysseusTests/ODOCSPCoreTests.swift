import XCTest
@testable import Feather

final class ODOCSPCoreTests: XCTestCase {
	func testParserBindsStatusToRequestedIssuerAndSerial() throws {
		let serial = Data([0x12, 0x34])
		let issuerNameHash = Data(repeating: 0x11, count: 20)
		let issuerKeyHash = Data(repeating: 0x22, count: 20)
		let response = makeGoodResponse(
			serial: serial,
			issuerNameHash: issuerNameHash,
			issuerKeyHash: issuerKeyHash
		)

		let parsed = try ODOCSPCore.parse(
			response: response,
			serial: serial,
			issuerNameHash: issuerNameHash,
			issuerKeyHash: issuerKeyHash
		)
		XCTAssertEqual(parsed.certStatus, .good)
		XCTAssertEqual(parsed.responderID, .byKey(Data(repeating: 0x33, count: 20)))

		let wrongIssuer = try ODOCSPCore.parse(
			response: response,
			serial: serial,
			issuerNameHash: Data(repeating: 0x44, count: 20),
			issuerKeyHash: issuerKeyHash
		)
		XCTAssertNil(wrongIssuer.certStatus)
	}

	func testParserRejectsWrongSerial() throws {
		let issuerNameHash = Data(repeating: 0x11, count: 20)
		let issuerKeyHash = Data(repeating: 0x22, count: 20)
		let response = makeGoodResponse(
			serial: Data([0x12, 0x34]),
			issuerNameHash: issuerNameHash,
			issuerKeyHash: issuerKeyHash
		)

		let parsed = try ODOCSPCore.parse(
			response: response,
			serial: Data([0x56, 0x78]),
			issuerNameHash: issuerNameHash,
			issuerKeyHash: issuerKeyHash
		)
		XCTAssertNil(parsed.certStatus)
	}

	private func makeGoodResponse(serial: Data, issuerNameHash: Data, issuerKeyHash: Data) -> Data {
		let certID = ODOCSPCore.certID(
			issuerNameHash: issuerNameHash,
			issuerKeyHash: issuerKeyHash,
			serial: serial
		)
		let timestamp = ODDER.tlv(0x18, Data("20261031120000Z".utf8))
		let thisUpdate = ODDER.tlv(0x18, Data("20261031115900Z".utf8))
		let nextUpdate = ODDER.tlv(0xA0, ODDER.tlv(0x18, Data("20261031130000Z".utf8)))
		let singleResponse = ODDER.sequence(
			certID,
			ODDER.tlv(0x80, Data()),
			thisUpdate,
			nextUpdate
		)
		let responderKeyHash = ODDER.tlv(0x82, Data(repeating: 0x33, count: 20))
		let responseData = ODDER.sequence(
			responderKeyHash,
			timestamp,
			ODDER.sequence(singleResponse)
		)
		let signatureAlgorithm = ODDER.sequence(ODDER.oid("1.2.840.113549.1.1.11"), ODDER.null)
		let signature = ODDER.tlv(0x03, Data([0x00, 0x01]))
		let basicResponse = ODDER.sequence(responseData, signatureAlgorithm, signature)
		let responseBytes = ODDER.sequence(
			ODDER.oid(ODOCSPCore.basicResponseOID),
			ODDER.octetString(basicResponse)
		)
		return ODDER.sequence(
			ODDER.tlv(0x0A, Data([0x00])),
			ODDER.tlv(0xA0, responseBytes)
		)
	}
}
