// SocketConstantsTests.swift
// Tests for HomeKitCore SocketConstants: token management, path computation, and protocol version.

import XCTest
import HomeKitCore

final class SocketConstantsTests: XCTestCase {

    // MARK: - Path Constants

    func testDefaultPathContainsAppSupportDir() {
        let path = SocketConstants.defaultPath
        // Should point to Application Support (not /tmp fallback) on a normal macOS system
        XCTAssertTrue(
            path.contains("Application Support/homekit-automator/homekitauto.sock")
            || path == "/tmp/homekitauto.sock",
            "defaultPath should be in Application Support or fallback to /tmp: \(path)"
        )
    }

    func testTokenPathContainsAuthToken() {
        let path = SocketConstants.tokenPath
        XCTAssertTrue(
            path.contains(".auth_token"),
            "tokenPath should contain .auth_token: \(path)"
        )
    }

    func testLegacySocketPath() {
        XCTAssertEqual(SocketConstants.legacySocketPath, "/tmp/homekitauto.sock")
    }

    func testProtocolVersion() {
        XCTAssertEqual(SocketConstants.protocolVersion, 1)
    }

    // MARK: - App Support Directory

    func testAppSupportDirNotNil() {
        // On a normal macOS system, appSupportDir should resolve successfully
        XCTAssertNotNil(SocketConstants.appSupportDir)
    }

    func testAppSupportDirContainsSubdirectory() {
        guard let dir = SocketConstants.appSupportDir else {
            XCTFail("appSupportDir returned nil")
            return
        }
        XCTAssertTrue(
            dir.path.contains("homekit-automator"),
            "appSupportDir should contain 'homekit-automator': \(dir.path)"
        )
    }

    // MARK: - Token Management

    func testGetOrCreateTokenReturnsUUID() {
        let token = SocketConstants.getOrCreateToken()
        XCTAssertFalse(token.isEmpty, "Token should not be empty")
        // UUID format: 8-4-4-4-12 hex digits
        XCTAssertNotNil(
            UUID(uuidString: token),
            "Token should be a valid UUID: \(token)"
        )
    }

    func testGetOrCreateTokenIdempotent() {
        // Calling getOrCreateToken() twice should return the same value
        let token1 = SocketConstants.getOrCreateToken()
        let token2 = SocketConstants.getOrCreateToken()
        XCTAssertEqual(token1, token2, "Subsequent calls should return the same token")
    }

    // MARK: - Token Validation

    func testValidateTokenCorrect() {
        let token = SocketConstants.getOrCreateToken()
        XCTAssertTrue(
            SocketConstants.validateToken(token),
            "Correct token should validate"
        )
    }

    func testValidateTokenWrong() {
        XCTAssertFalse(
            SocketConstants.validateToken("definitely-not-the-right-token"),
            "Wrong token should not validate"
        )
    }

    func testValidateTokenNil() {
        XCTAssertFalse(
            SocketConstants.validateToken(nil),
            "Nil token should not validate"
        )
    }

    func testValidateTokenEmpty() {
        XCTAssertFalse(
            SocketConstants.validateToken(""),
            "Empty token should not validate"
        )
    }
}
