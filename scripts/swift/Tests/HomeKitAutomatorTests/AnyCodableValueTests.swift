// AnyCodableValueTests.swift
// Comprehensive tests for AnyCodableValue: decode priority, display strings, raw values,
// typed accessors, equatable behavior, and round-trip encoding.

import XCTest
import HomeKitCore

final class AnyCodableValueTests: XCTestCase {

    // MARK: - Helpers

    /// Decode a JSON string into AnyCodableValue.
    private func decode(_ json: String) throws -> AnyCodableValue {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(AnyCodableValue.self, from: data)
    }

    /// Round-trip encode then decode an AnyCodableValue.
    private func roundTrip(_ value: AnyCodableValue) throws -> AnyCodableValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(AnyCodableValue.self, from: data)
    }

    // MARK: - Decode Priority Tests

    func testDecodeNull() throws {
        let value = try decode("null")
        XCTAssertEqual(value, .null)
    }

    func testDecodeBoolTrue() throws {
        let value = try decode("true")
        XCTAssertEqual(value, .bool(true))
    }

    func testDecodeBoolFalse() throws {
        let value = try decode("false")
        XCTAssertEqual(value, .bool(false))
    }

    func testDecodeInt() throws {
        let value = try decode("42")
        XCTAssertEqual(value, .int(42))
    }

    func testDecodeNegativeInt() throws {
        let value = try decode("-7")
        XCTAssertEqual(value, .int(-7))
    }

    func testDecodeZero() throws {
        let value = try decode("0")
        // 0 should decode as int, NOT bool
        XCTAssertEqual(value, .int(0))
    }

    func testDecodeOne() throws {
        let value = try decode("1")
        // 1 should decode as int, NOT bool
        XCTAssertEqual(value, .int(1))
    }

    func testDecodeDouble() throws {
        let value = try decode("3.14")
        XCTAssertEqual(value, .double(3.14))
    }

    func testDecodeDoubleWithFractionalZero() throws {
        // JSON 1.0 is indistinguishable from 1 at the NSNumber level,
        // so the decoder's int-before-double priority means it decodes as .int(1)
        let value = try decode("1.0")
        XCTAssertEqual(value, .int(1))
    }

    func testDecodeString() throws {
        let value = try decode("\"hello\"")
        XCTAssertEqual(value, .string("hello"))
    }

    func testDecodeStringTrue() throws {
        // "true" as a JSON string should remain .string, not become .bool
        let value = try decode("\"true\"")
        XCTAssertEqual(value, .string("true"))
    }

    func testDecodeStringNumber() throws {
        // "42" as a JSON string should remain .string, not become .int
        let value = try decode("\"42\"")
        XCTAssertEqual(value, .string("42"))
    }

    func testDecodeEmptyArray() throws {
        let value = try decode("[]")
        XCTAssertEqual(value, .array([]))
    }

    func testDecodeArray() throws {
        let value = try decode("[1, \"two\", true]")
        XCTAssertEqual(value, .array([.int(1), .string("two"), .bool(true)]))
    }

    func testDecodeEmptyDictionary() throws {
        let value = try decode("{}")
        XCTAssertEqual(value, .dictionary([:]))
    }

    func testDecodeDictionary() throws {
        let value = try decode("{\"key\": \"value\", \"num\": 5}")
        XCTAssertEqual(value, .dictionary(["key": .string("value"), "num": .int(5)]))
    }

    func testDecodeNestedStructure() throws {
        let json = "{\"items\": [1, {\"nested\": true}]}"
        let value = try decode(json)
        let expected: AnyCodableValue = .dictionary([
            "items": .array([
                .int(1),
                .dictionary(["nested": .bool(true)])
            ])
        ])
        XCTAssertEqual(value, expected)
    }

    // MARK: - Display String Tests

    func testDisplayStringString() {
        XCTAssertEqual(AnyCodableValue.string("hello").displayString, "hello")
    }

    func testDisplayStringInt() {
        XCTAssertEqual(AnyCodableValue.int(42).displayString, "42")
    }

    func testDisplayStringDouble() {
        // Double uses %.1f format
        XCTAssertEqual(AnyCodableValue.double(72.0).displayString, "72.0")
        XCTAssertEqual(AnyCodableValue.double(3.14159).displayString, "3.1")
    }

    func testDisplayStringBool() {
        XCTAssertEqual(AnyCodableValue.bool(true).displayString, "true")
        XCTAssertEqual(AnyCodableValue.bool(false).displayString, "false")
    }

    func testDisplayStringNull() {
        XCTAssertEqual(AnyCodableValue.null.displayString, "null")
    }

    func testDisplayStringArray() {
        let value = AnyCodableValue.array([.int(1), .string("two")])
        XCTAssertEqual(value.displayString, "[1, two]")
    }

    func testDisplayStringDictionary() {
        let value = AnyCodableValue.dictionary(["key": .string("val")])
        XCTAssertEqual(value.displayString, "key: val")
    }

    // MARK: - Description (CustomStringConvertible) Tests

    func testDescriptionString() {
        XCTAssertEqual(AnyCodableValue.string("abc").description, "abc")
    }

    func testDescriptionInt() {
        XCTAssertEqual(AnyCodableValue.int(99).description, "99")
    }

    func testDescriptionDouble() {
        // Description uses default formatting (not %.1f)
        let desc = AnyCodableValue.double(3.14).description
        XCTAssertTrue(desc.contains("3.14"), "Description should contain the double value: \(desc)")
    }

    func testDescriptionBool() {
        XCTAssertEqual(AnyCodableValue.bool(true).description, "true")
    }

    func testDescriptionNull() {
        XCTAssertEqual(AnyCodableValue.null.description, "null")
    }

    // MARK: - Typed Accessor Tests

    func testStringValueAccessor() {
        XCTAssertEqual(AnyCodableValue.string("hi").stringValue, "hi")
        XCTAssertNil(AnyCodableValue.int(5).stringValue)
        XCTAssertNil(AnyCodableValue.bool(true).stringValue)
    }

    func testIntValueAccessor() {
        XCTAssertEqual(AnyCodableValue.int(42).intValue, 42)
        XCTAssertNil(AnyCodableValue.string("42").intValue)
        XCTAssertNil(AnyCodableValue.double(42.0).intValue)
    }

    func testDoubleValueAccessor() {
        XCTAssertEqual(AnyCodableValue.double(3.14).doubleValue, 3.14)
        // Int coercion: int values should be accessible as double
        XCTAssertEqual(AnyCodableValue.int(75).doubleValue, 75.0)
        XCTAssertNil(AnyCodableValue.string("3.14").doubleValue)
    }

    func testBoolValueAccessor() {
        XCTAssertEqual(AnyCodableValue.bool(true).boolValue, true)
        XCTAssertEqual(AnyCodableValue.bool(false).boolValue, false)
        XCTAssertNil(AnyCodableValue.int(1).boolValue)
        XCTAssertNil(AnyCodableValue.string("true").boolValue)
    }

    func testArrayValueAccessor() {
        let arr: [AnyCodableValue] = [.int(1), .int(2)]
        XCTAssertEqual(AnyCodableValue.array(arr).arrayValue, arr)
        XCTAssertNil(AnyCodableValue.string("[]").arrayValue)
    }

    func testDictionaryValueAccessor() {
        let dict: [String: AnyCodableValue] = ["a": .int(1)]
        XCTAssertEqual(AnyCodableValue.dictionary(dict).dictionaryValue, dict)
        XCTAssertNil(AnyCodableValue.string("{}").dictionaryValue)
    }

    func testNullAccessorsReturnNil() {
        let null = AnyCodableValue.null
        XCTAssertNil(null.stringValue)
        XCTAssertNil(null.intValue)
        XCTAssertNil(null.doubleValue)
        XCTAssertNil(null.boolValue)
        XCTAssertNil(null.arrayValue)
        XCTAssertNil(null.dictionaryValue)
    }

    // MARK: - Raw Value Tests

    func testRawValueString() {
        let raw = AnyCodableValue.string("hello").rawValue
        XCTAssertEqual(raw as? String, "hello")
    }

    func testRawValueInt() {
        let raw = AnyCodableValue.int(42).rawValue
        XCTAssertEqual(raw as? Int, 42)
    }

    func testRawValueDouble() {
        let raw = AnyCodableValue.double(3.14).rawValue
        XCTAssertEqual(raw as? Double, 3.14)
    }

    func testRawValueBool() {
        let raw = AnyCodableValue.bool(true).rawValue
        XCTAssertEqual(raw as? Bool, true)
    }

    func testRawValueNull() {
        let raw = AnyCodableValue.null.rawValue
        XCTAssertTrue(raw is NSNull, "null rawValue should be NSNull")
    }

    func testRawValueArray() {
        let raw = AnyCodableValue.array([.int(1), .string("two")]).rawValue
        guard let arr = raw as? [Any] else {
            XCTFail("rawValue should be [Any]")
            return
        }
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr[0] as? Int, 1)
        XCTAssertEqual(arr[1] as? String, "two")
    }

    func testRawValueDictionary() {
        let raw = AnyCodableValue.dictionary(["key": .bool(true)]).rawValue
        guard let dict = raw as? [String: Any] else {
            XCTFail("rawValue should be [String: Any]")
            return
        }
        XCTAssertEqual(dict["key"] as? Bool, true)
    }

    // MARK: - Equatable Tests

    func testEqualSameCase() {
        XCTAssertEqual(AnyCodableValue.int(5), AnyCodableValue.int(5))
        XCTAssertEqual(AnyCodableValue.string("a"), AnyCodableValue.string("a"))
    }

    func testNotEqualDifferentCases() {
        // .int(1) and .double(1.0) are different cases even though numerically equivalent
        XCTAssertNotEqual(AnyCodableValue.int(1), AnyCodableValue.double(1.0))
        XCTAssertNotEqual(AnyCodableValue.int(0), AnyCodableValue.bool(false))
    }

    func testNotEqualDifferentValues() {
        XCTAssertNotEqual(AnyCodableValue.int(1), AnyCodableValue.int(2))
        XCTAssertNotEqual(AnyCodableValue.string("a"), AnyCodableValue.string("b"))
    }

    func testNestedDictionaryEquality() {
        let a = AnyCodableValue.dictionary(["x": .array([.int(1), .null])])
        let b = AnyCodableValue.dictionary(["x": .array([.int(1), .null])])
        XCTAssertEqual(a, b)
    }

    // MARK: - Round-Trip Encoding Tests

    func testRoundTripString() throws {
        XCTAssertEqual(try roundTrip(.string("round")), .string("round"))
    }

    func testRoundTripInt() throws {
        XCTAssertEqual(try roundTrip(.int(99)), .int(99))
    }

    func testRoundTripDouble() throws {
        XCTAssertEqual(try roundTrip(.double(2.718)), .double(2.718))
    }

    func testRoundTripBool() throws {
        XCTAssertEqual(try roundTrip(.bool(true)), .bool(true))
        XCTAssertEqual(try roundTrip(.bool(false)), .bool(false))
    }

    func testRoundTripNull() throws {
        XCTAssertEqual(try roundTrip(.null), .null)
    }

    func testRoundTripNested() throws {
        let original = AnyCodableValue.dictionary([
            "items": .array([.int(1), .string("two"), .null]),
            "flag": .bool(true)
        ])
        XCTAssertEqual(try roundTrip(original), original)
    }
}
