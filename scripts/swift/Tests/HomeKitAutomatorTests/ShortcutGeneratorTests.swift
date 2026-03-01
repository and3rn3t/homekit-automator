// ShortcutGeneratorTests.swift
// Tests for ShortcutGenerator plist generation and structure validation.
// swiftlint:disable force_cast

import XCTest
@testable import homekitauto

final class ShortcutGeneratorTests: XCTestCase {

    var tempDir: URL!
    let generator = ShortcutGenerator()

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hka-shortcut-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func outputPath(_ name: String) -> URL {
        tempDir.appendingPathComponent("\(name).shortcut")
    }

    private func parsePlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let result = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        guard let dict = result as? [String: Any] else {
            XCTFail("Plist is not a dictionary")
            return [:]
        }
        return dict
    }

    private func workflowActions(from plist: [String: Any]) -> [[String: Any]] {
        plist["WFWorkflowActions"] as? [[String: Any]] ?? []
    }

    // MARK: - Tests

    func testGenerateScheduleTrigger() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "light-001",
                deviceName: "Kitchen Lights",
                characteristic: "power",
                value: .bool(true),
                delaySeconds: 0
            )
        ]

        let path = outputPath("schedule")
        try generator.generate(name: "HKA: Morning Lights", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // Comment action + 1 device action = 2
        XCTAssertEqual(wfActions.count, 2)

        // First action is the identifying comment
        XCTAssertEqual(
            wfActions[0]["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.comment"
        )

        // Second action is the HomeKit set action
        let setAction = wfActions[1]
        XCTAssertEqual(
            setAction["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.homekit.set"
        )

        let params = setAction["WFWorkflowActionParameters"] as! [String: Any]
        let accessory = params["WFHomeAccessory"] as! [String: Any]
        XCTAssertEqual(accessory["id"] as? String, "light-001")
        XCTAssertEqual(accessory["name"] as? String, "Kitchen Lights")
        XCTAssertEqual(params["WFHomeCharacteristic"] as? String, "power")
        XCTAssertEqual(params["WFHomeValue"] as? Bool, true)

        // Verify minimum client version
        XCTAssertEqual(plist["WFWorkflowMinimumClientVersion"] as? Int, 900)
    }

    func testGenerateSolarTrigger() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "light-002",
                deviceName: "Porch Light",
                characteristic: "power",
                value: .bool(true),
                delaySeconds: 0
            )
        ]

        let path = outputPath("solar")
        try generator.generate(name: "HKA: Sunset Porch", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        XCTAssertEqual(wfActions.count, 2)

        // Verify plist metadata
        XCTAssertEqual(plist["WFWorkflowMinimumClientVersion"] as? Int, 900)
        XCTAssertNotNil(plist["WFWorkflowIcon"])
        XCTAssertEqual(plist["WFWorkflowHasShortcutInputVariables"] as? Bool, false)

        // Verify workflow types include NCWidget and WatchKit
        let types = plist["WFWorkflowTypes"] as? [String]
        XCTAssertNotNil(types)
        XCTAssertTrue(types?.contains("NCWidget") ?? false)
        XCTAssertTrue(types?.contains("WatchKit") ?? false)

        // Verify the device action
        let setAction = wfActions[1]
        let params = setAction["WFWorkflowActionParameters"] as! [String: Any]
        let accessory = params["WFHomeAccessory"] as! [String: Any]
        XCTAssertEqual(accessory["name"] as? String, "Porch Light")
    }

    func testGenerateManualTrigger() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "lock-001",
                deviceName: "Front Door Lock",
                characteristic: "lockState",
                value: .int(1),
                delaySeconds: 0
            )
        ]

        let path = outputPath("manual")
        try generator.generate(name: "HKA: Lock Up", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        XCTAssertEqual(wfActions.count, 2)

        // Verify the set action with integer value
        let setAction = wfActions[1]
        let params = setAction["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(params["WFHomeCharacteristic"] as? String, "lockState")
        XCTAssertEqual(params["WFHomeValue"] as? Int, 1)

        // Verify icon structure
        let icon = plist["WFWorkflowIcon"] as? [String: Any]
        XCTAssertNotNil(icon)
        XCTAssertNotNil(icon?["WFWorkflowIconStartColor"])
        XCTAssertNotNil(icon?["WFWorkflowIconGlyphNumber"])
    }

    func testGenerateMultipleActions() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "light-001",
                deviceName: "Kitchen Lights",
                characteristic: "power",
                value: .bool(true),
                delaySeconds: 0
            ),
            AutomationAction(
                deviceUuid: "light-002",
                deviceName: "Living Room Lights",
                characteristic: "brightness",
                value: .int(75),
                delaySeconds: 0
            ),
            AutomationAction(
                deviceUuid: "therm-001",
                deviceName: "Thermostat",
                characteristic: "targetTemperature",
                value: .double(72.0),
                delaySeconds: 0
            ),
        ]

        let path = outputPath("multiple")
        try generator.generate(name: "HKA: Morning Routine", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // 1 comment + 3 device actions = 4
        XCTAssertEqual(wfActions.count, 4)

        // All non-comment actions should be homekit.set
        for i in 1..<wfActions.count {
            XCTAssertEqual(
                wfActions[i]["WFWorkflowActionIdentifier"] as? String,
                "is.workflow.actions.homekit.set"
            )
        }

        // Verify each action's value type
        let params1 = wfActions[1]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(params1["WFHomeValue"] as? Bool, true)

        let params2 = wfActions[2]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(params2["WFHomeValue"] as? Int, 75)

        let params3 = wfActions[3]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(params3["WFHomeValue"] as? Double, 72.0)
    }

    func testGenerateSceneAction() throws {
        let actions = [
            AutomationAction(
                type: "scene",
                sceneName: "Good Night",
                sceneUuid: "scene-001"
            )
        ]

        let path = outputPath("scene")
        try generator.generate(name: "HKA: Good Night", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // 1 comment + 1 scene action = 2
        XCTAssertEqual(wfActions.count, 2)

        let sceneAction = wfActions[1]
        XCTAssertEqual(
            sceneAction["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.homekit.scene"
        )

        let params = sceneAction["WFWorkflowActionParameters"] as! [String: Any]
        let scene = params["WFHomeScene"] as! [String: Any]
        XCTAssertEqual(scene["id"] as? String, "scene-001")
        XCTAssertEqual(scene["name"] as? String, "Good Night")
    }

    func testGenerateDelayAction() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "light-001",
                deviceName: "Kitchen Lights",
                characteristic: "power",
                value: .bool(true),
                delaySeconds: 5
            ),
            AutomationAction(
                deviceUuid: "light-002",
                deviceName: "Living Room Lights",
                characteristic: "power",
                value: .bool(true),
                delaySeconds: 0
            ),
        ]

        let path = outputPath("delay")
        try generator.generate(name: "HKA: Staggered Lights", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // 1 comment + 1 delay + 1 set (Kitchen) + 1 set (Living Room) = 4
        XCTAssertEqual(wfActions.count, 4)

        // Second action should be the delay
        XCTAssertEqual(
            wfActions[1]["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.delay"
        )
        let delayParams = wfActions[1]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(delayParams["WFDelayTime"] as? Int, 5)

        // Third action is the device control for the delayed action
        XCTAssertEqual(
            wfActions[2]["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.homekit.set"
        )

        // Fourth action is the non-delayed device control
        XCTAssertEqual(
            wfActions[3]["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.homekit.set"
        )
    }

    func testShortcutNameConvention() throws {
        // Verify HKA: prefix naming convention
        let shortcutName = "HKA: My Automation"
        XCTAssertTrue(shortcutName.hasPrefix("HKA: "))

        let actions = [
            AutomationAction(
                deviceUuid: "dev-001",
                deviceName: "Device",
                characteristic: "power",
                value: .bool(true),
                delaySeconds: 0
            )
        ]

        let path = outputPath("convention")
        try generator.generate(name: shortcutName, actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // Verify the comment action identifies the shortcut as HKA-generated
        let commentAction = wfActions[0]
        XCTAssertEqual(
            commentAction["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.comment"
        )
        let commentParams = commentAction["WFWorkflowActionParameters"] as! [String: Any]
        let commentText = commentParams["WFCommentActionText"] as? String
        XCTAssertNotNil(commentText)
        XCTAssertTrue(commentText?.contains("HomeKit Automator") ?? false)

        // Verify a RegisteredAutomation would have the HKA: prefix
        let automation = RegisteredAutomation(
            id: "test",
            name: "My Automation",
            trigger: AutomationTrigger(type: "manual", humanReadable: "manual"),
            conditions: nil,
            actions: actions,
            enabled: true,
            shortcutName: shortcutName,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        XCTAssertTrue(automation.shortcutName.hasPrefix("HKA: "))
    }

    // MARK: - Edge Cases

    func testStringValueInHomeKitSetAction() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "uuid-str",
                deviceName: "Thermostat",
                characteristic: "hvacMode",
                value: .string("heat"),
                delaySeconds: 0
            )
        ]

        let path = outputPath("string-value")
        try generator.generate(name: "String Value", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // Comment + 1 device action = 2
        XCTAssertEqual(wfActions.count, 2)

        let params = wfActions[1]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(params["WFHomeValue"] as? String, "heat")
    }

    func testNullValueFallsBackToStringRepresentation() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "uuid-null",
                deviceName: "Device",
                characteristic: "power",
                value: .null,
                delaySeconds: 0
            )
        ]

        let path = outputPath("null-value")
        try generator.generate(name: "Null Value", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)
        let params = wfActions[1]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertNotNil(params["WFHomeValue"], "Null value should still produce a WFHomeValue entry")
    }

    func testArrayValueFallsBackToStringRepresentation() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "uuid-arr",
                deviceName: "Device",
                characteristic: "custom",
                value: .array([.int(1), .int(2)]),
                delaySeconds: 0
            )
        ]

        let path = outputPath("array-value")
        try generator.generate(name: "Array Value", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)
        let params = wfActions[1]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertNotNil(params["WFHomeValue"])
        // Default case produces a string representation
        XCTAssertTrue(params["WFHomeValue"] is String)
    }

    func testEmptyActionsProducesOnlyComment() throws {
        let actions: [AutomationAction] = []

        let path = outputPath("empty-actions")
        try generator.generate(name: "Empty", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // Only the comment action
        XCTAssertEqual(wfActions.count, 1)
        XCTAssertEqual(
            wfActions[0]["WFWorkflowActionIdentifier"] as? String,
            "is.workflow.actions.comment"
        )
    }

    func testSceneActionWithMissingUuidIsSkipped() throws {
        let actions = [
            AutomationAction(
                type: "scene",
                deviceUuid: "",
                deviceName: "",
                characteristic: "",
                value: .null,
                delaySeconds: 0,
                sceneName: "Living Room",
                sceneUuid: nil
            )
        ]

        let path = outputPath("scene-no-uuid")
        try generator.generate(name: "No UUID", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // Only the comment action; scene action should be skipped
        XCTAssertEqual(wfActions.count, 1)
    }

    func testSceneActionWithMissingNameIsSkipped() throws {
        let actions = [
            AutomationAction(
                type: "scene",
                deviceUuid: "",
                deviceName: "",
                characteristic: "",
                value: .null,
                delaySeconds: 0,
                sceneName: nil,
                sceneUuid: "scene-123"
            )
        ]

        let path = outputPath("scene-no-name")
        try generator.generate(name: "No Name", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)

        // Only the comment action; scene action should be skipped
        XCTAssertEqual(wfActions.count, 1)
    }

    func testDoubleValueInHomeKitSetAction() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "uuid-dbl",
                deviceName: "Thermostat",
                characteristic: "targetTemperature",
                value: .double(22.5),
                delaySeconds: 0
            )
        ]

        let path = outputPath("double-value")
        try generator.generate(name: "Double Value", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)
        let params = wfActions[1]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(params["WFHomeValue"] as! Double, 22.5, accuracy: 0.01)
    }

    func testIntValueInHomeKitSetAction() throws {
        let actions = [
            AutomationAction(
                deviceUuid: "uuid-int",
                deviceName: "Light",
                characteristic: "brightness",
                value: .int(75),
                delaySeconds: 0
            )
        ]

        let path = outputPath("int-value")
        try generator.generate(name: "Int Value", actions: actions, outputPath: path)

        let plist = try parsePlist(at: path)
        let wfActions = workflowActions(from: plist)
        let params = wfActions[1]["WFWorkflowActionParameters"] as! [String: Any]
        XCTAssertEqual(params["WFHomeValue"] as? Int, 75)
    }
}
