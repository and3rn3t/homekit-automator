// SocketClientTests.swift
// Tests for SocketClient data types: Request/Response Codable conformance,
// Response.isOk computed property, and SocketError descriptions.
// swiftlint:disable force_cast

import XCTest
@testable import homekitauto
import HomeKitCore

final class SocketClientTests: XCTestCase {

    // MARK: - Request Encoding

    func testRequestEncodesAllFields() throws {
        let request = SocketClient.Request(
            id: "test-123",
            command: "get_scenes",
            params: ["room": .string("Living Room")],
            token: "abc-token",
            version: 1
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["id"] as? String, "test-123")
        XCTAssertEqual(json["command"] as? String, "get_scenes")
        XCTAssertEqual(json["token"] as? String, "abc-token")
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertNotNil(json["params"])
    }

    func testRequestEncodesNilOptionals() throws {
        let request = SocketClient.Request(
            id: "test-456",
            command: "status",
            params: nil,
            token: nil,
            version: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["id"] as? String, "test-456")
        XCTAssertEqual(json["command"] as? String, "status")
        XCTAssertNil(json["params"])
        XCTAssertNil(json["token"])
        XCTAssertNil(json["version"])
    }

    func testRequestRoundTrip() throws {
        let request = SocketClient.Request(
            id: "round-trip",
            command: "turn_on_accessory",
            params: [
                "name": .string("Living Room Light"),
                "brightness": .int(80),
                "on": .bool(true)
            ],
            token: "tok-999",
            version: 2
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SocketClient.Request.self, from: data)

        XCTAssertEqual(decoded.id, "round-trip")
        XCTAssertEqual(decoded.command, "turn_on_accessory")
        XCTAssertEqual(decoded.token, "tok-999")
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.params?["name"], .string("Living Room Light"))
        XCTAssertEqual(decoded.params?["brightness"], .int(80))
        XCTAssertEqual(decoded.params?["on"], .bool(true))
    }

    // MARK: - Response Decoding

    func testResponseIsOkTrue() throws {
        let json = """
        {"id":"r1","status":"ok","data":null,"error":null}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SocketClient.Response.self, from: json)

        XCTAssertTrue(response.isOk)
        XCTAssertEqual(response.id, "r1")
        XCTAssertEqual(response.status, "ok")
    }

    func testResponseIsOkFalse() throws {
        let json = """
        {"id":"r2","status":"error","data":null,"error":"Something went wrong"}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SocketClient.Response.self, from: json)

        XCTAssertFalse(response.isOk)
        XCTAssertEqual(response.error, "Something went wrong")
    }

    func testResponseIsOkFalseForArbitraryStatus() throws {
        let json = """
        {"id":"r3","status":"unknown","data":null,"error":null}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SocketClient.Response.self, from: json)

        XCTAssertFalse(response.isOk)
    }

    func testResponseWithDictionaryData() throws {
        let json = """
        {"id":"r4","status":"ok","data":{"name":"Living Room","temperature":22.5}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SocketClient.Response.self, from: json)

        XCTAssertTrue(response.isOk)
        if case .dictionary(let dict) = response.data {
            XCTAssertEqual(dict["name"], .string("Living Room"))
            XCTAssertEqual(dict["temperature"], .double(22.5))
        } else {
            XCTFail("Expected dictionary data, got \(String(describing: response.data))")
        }
    }

    func testResponseWithArrayData() throws {
        let json = """
        {"id":"r5","status":"ok","data":["Scene A","Scene B"]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SocketClient.Response.self, from: json)

        XCTAssertTrue(response.isOk)
        if case .array(let arr) = response.data {
            XCTAssertEqual(arr.count, 2)
            XCTAssertEqual(arr[0], .string("Scene A"))
        } else {
            XCTFail("Expected array data, got \(String(describing: response.data))")
        }
    }

    func testResponseWithStringData() throws {
        let json = """
        {"id":"r6","status":"ok","data":"connected"}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SocketClient.Response.self, from: json)

        if case .string(let str) = response.data {
            XCTAssertEqual(str, "connected")
        } else {
            XCTFail("Expected string data")
        }
    }

    func testResponseWithNullData() throws {
        let json = """
        {"id":"r7","status":"ok","data":null}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SocketClient.Response.self, from: json)

        XCTAssertTrue(response.isOk)
        // data can be nil or .null depending on JSON null handling
        if let data = response.data {
            XCTAssertEqual(data, .null)
        }
    }

    func testResponseRoundTrip() throws {
        let response = SocketClient.Response(
            id: "rt-1",
            status: "ok",
            data: .dictionary([
                "homes": .int(2),
                "connected": .bool(true)
            ]),
            error: nil
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SocketClient.Response.self, from: data)

        XCTAssertEqual(decoded.id, "rt-1")
        XCTAssertEqual(decoded.status, "ok")
        XCTAssertTrue(decoded.isOk)
        XCTAssertNil(decoded.error)
    }

    // MARK: - SocketError Descriptions

    func testConnectionFailedDescription() {
        let error = SocketError.connectionFailed("Could not connect")
        XCTAssertEqual(error.errorDescription, "Could not connect")
    }

    func testSendFailedDescription() {
        let error = SocketError.sendFailed("Bytes mismatch")
        XCTAssertEqual(error.errorDescription, "Bytes mismatch")
    }

    func testNoResponseDescription() {
        let error = SocketError.noResponse("Timeout")
        XCTAssertEqual(error.errorDescription, "Timeout")
    }

    func testResponseMismatchDescription() {
        let error = SocketError.responseMismatch("ID mismatch")
        XCTAssertEqual(error.errorDescription, "ID mismatch")
    }

    func testHelperErrorDescription() {
        let error = SocketError.helperError("Device not found")
        XCTAssertEqual(error.errorDescription, "Device not found")
    }

    func testSocketErrorPreservesAssociatedValues() {
        let errors: [(SocketError, String)] = [
            (.connectionFailed("msg1"), "msg1"),
            (.sendFailed("msg2"), "msg2"),
            (.noResponse("msg3"), "msg3"),
            (.responseMismatch("msg4"), "msg4"),
            (.helperError("msg5"), "msg5"),
        ]
        for (error, expected) in errors {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    // MARK: - JSON-NL Protocol

    func testRequestEncodesAsValidJSONNL() throws {
        let request = SocketClient.Request(
            id: "nl-test",
            command: "status",
            params: nil,
            token: nil,
            version: 1
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        var data = try encoder.encode(request)
        data.append(contentsOf: "\n".utf8)

        let string = String(data: data, encoding: .utf8)!
        // Must end with exactly one newline
        XCTAssertTrue(string.hasSuffix("\n"))
        // Must not contain embedded newlines (single-line JSON)
        let withoutTrailing = String(string.dropLast())
        XCTAssertFalse(withoutTrailing.contains("\n"))
        // Must be valid JSON when stripped
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: withoutTrailing.data(using: .utf8)!))
    }
}
