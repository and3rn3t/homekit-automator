/// JSONOutput.swift
///
/// Shared helper that encodes an `Encodable` value as pretty-printed JSON and
/// writes it to stdout.  Every CLI command used to duplicate this 4-line pattern;
/// now they all call `printJSON(_:sortedKeys:)` instead.

import Foundation

/// Encodes a value as pretty-printed JSON and prints it to stdout.
///
/// - Parameters:
///   - value: Any `Encodable` value to serialise.
///   - sortedKeys: Sort dictionary keys alphabetically in the output (default: true).
func printJSON<T: Encodable>(_ value: T, sortedKeys: Bool = true) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = sortedKeys ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted]
    let data = try encoder.encode(value)
    print(String(data: data, encoding: .utf8) ?? "{}")
}
