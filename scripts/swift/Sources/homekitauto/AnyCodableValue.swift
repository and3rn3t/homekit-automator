// AnyCodableValue.swift
// Type-erased Codable wrapper for heterogeneous JSON values.

import Foundation

/// A type-erased Codable value that can represent any JSON-compatible type.
///
/// HomeKit values are inherently heterogeneous: an accessory's state can be represented by different data types
/// depending on the characteristic type. For example:
/// - **Power state**: Boolean (on/off)
/// - **Brightness**: Integer (0-100)
/// - **Color temperature**: Float/Double (in Kelvin)
/// - **Scene metadata**: String or nested dictionary
/// - **Sensor arrays**: Arrays of values
///
/// This enum provides a unified, type-erased representation that can hold any of these types and be transparently
/// encoded to/decoded from JSON. Each case corresponds to a JSON value type, and typed accessors (intValue, doubleValue, etc.)
/// allow safe extraction of expected types.
///
/// Used throughout the socket protocol and command response handling where the exact structure of values cannot be
/// determined statically, enabling flexible HomeKit automation across diverse accessory types.
enum AnyCodableValue: Codable, Sendable, CustomStringConvertible {
    /// String value. Typically used for names, identifiers, modes (e.g., "heating", "cooling"),
    /// and other textual HomeKit characteristic values.
    case string(String)

    /// Integer value. Commonly used for discrete numeric characteristics like brightness (0-100),
    /// hue (0-360), saturation (0-100), target temperature (in whole degrees), and other integer-valued traits.
    case int(Int)

    /// Double-precision floating-point value. Used for continuous numeric characteristics like
    /// current temperature (e.g., 21.5°C), humidity percentage (e.g., 45.2%), and other fractional values.
    case double(Double)

    /// Boolean value. Used for binary switch states, occupancy detection, lock status (locked/unlocked),
    /// and other on/off or true/false HomeKit characteristics.
    case bool(Bool)

    /// Array of heterogeneous values. Used for multi-valued responses such as lists of scenes,
    /// accessory lists, or structured arrays of mixed-type data from HomeKit queries.
    case array([AnyCodableValue])

    /// Nested dictionary with string keys and heterogeneous values. Used for complex structured data
    /// such as accessory metadata, scene configuration objects, and other nested HomeKit information.
    case dictionary([String: AnyCodableValue])

    /// Null/nil value. Represents the absence of data or explicitly null JSON values.
    case null

    var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return "\(b)"
        case .array(let a): return "\(a)"
        case .dictionary(let d): return "\(d)"
        case .null: return "null"
        }
    }

    /// Extracts the string value, or returns nil if this value is not a string.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Extracts the integer value, or returns nil if this value is not an integer.
    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    /// Extracts the double value, or returns nil if this value is not numeric.
    /// Special behavior: if the value is an integer, it is automatically coerced to a Double.
    /// This is useful for commands that require fractional values (temperatures, percentages) but receive
    /// whole numbers from HomeKit. For example, brightness (integer 75) can be treated as (double 75.0).
    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    /// Extracts the boolean value, or returns nil if this value is not a boolean.
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Extracts the array value, or returns nil if this value is not an array.
    var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Extracts the dictionary value, or returns nil if this value is not a dictionary.
    var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }

    // MARK: - Codable

    /// Decodes a JSON value into the appropriate AnyCodableValue case using a priority-based strategy.
    ///
    /// The decoder attempts to decode in this priority order:
    /// 1. **null**: Returns `.null` if the JSON value is explicitly null.
    /// 2. **bool**: Returns `.bool` if the value decodes as a JSON boolean (true/false).
    /// 3. **int**: Returns `.int` if the value decodes as a JSON number without a fractional part.
    /// 4. **double**: Returns `.double` if the value decodes as a JSON floating-point number.
    /// 5. **string**: Returns `.string` if the value is a JSON string.
    /// 6. **array**: Returns `.array` if the value is a JSON array (recursively decoding elements).
    /// 7. **dict**: Returns `.dictionary` if the value is a JSON object (recursively decoding values).
    ///
    /// If none of these succeed, a `DecodingError.dataCorruptedError` is thrown.
    /// This priority order ensures that numbers are captured at the most specific type first (bool > int > double)
    /// and prevents numeric values from accidentally being treated as strings.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([AnyCodableValue].self) {
            self = .array(a)
        } else if let d = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(d)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnyCodableValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        case .null: try container.encodeNil()
        }
    }
}
