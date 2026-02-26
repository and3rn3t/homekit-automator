/**
 * MCP Server Integration Tests
 *
 * Tests the HomeKit Automator MCP server's JSON-RPC protocol conformance and
 * CLI argument assembly for all 11 tools. Uses a mock CLI (mock-cli.js) that
 * echoes received arguments back in the response so tests can verify the
 * server builds the correct command lines.
 *
 * Run: node --test test/mcp-server.test.js
 */

import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, symlinkSync, chmodSync, rmSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SERVER_PATH = resolve(__dirname, "..", "index.js");
const MOCK_CLI_PATH = resolve(__dirname, "mock-cli.js");

// ─── Test Client ─────────────────────────────────────────────────────────────

/**
 * Manages an MCP server child process, providing helpers to send JSON-RPC
 * requests and wait for responses over stdin/stdout.
 */
class MCPTestClient {
  constructor() {
    this.serverProcess = null;
    this.pendingResolvers = new Map();
    this.nextId = 1;
    this.tmpDir = null;
  }

  /** Start the MCP server with the mock CLI on PATH. */
  async start() {
    // Create a temp directory with a symlink named "homekitauto" → mock-cli.js
    this.tmpDir = mkdtempSync(join(tmpdir(), "mcp-test-"));
    const mockLink = join(this.tmpDir, "homekitauto");
    chmodSync(MOCK_CLI_PATH, 0o755);
    symlinkSync(MOCK_CLI_PATH, mockLink);

    const env = {
      ...process.env,
      PATH: `${this.tmpDir}:${process.env.PATH}`,
    };

    this.serverProcess = spawn("node", [SERVER_PATH], {
      env,
      stdio: ["pipe", "pipe", "pipe"],
    });

    // Parse newline-delimited JSON-RPC responses from stdout
    let buffer = "";
    this.serverProcess.stdout.on("data", (data) => {
      buffer += data.toString();
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const response = JSON.parse(line);
          if (response.id != null) {
            const resolver = this.pendingResolvers.get(response.id);
            if (resolver) {
              resolver(response);
              this.pendingResolvers.delete(response.id);
            }
          }
        } catch {
          // Ignore non-JSON output
        }
      }
    });

    // Give the server a moment to start
    await new Promise((r) => setTimeout(r, 300));
  }

  /** Send a JSON-RPC request and wait for the response. */
  send(method, params = {}) {
    const id = this.nextId++;
    const message = { jsonrpc: "2.0", id, method, params };

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingResolvers.delete(id);
        reject(
          new Error(`Timeout waiting for response to ${method} (id: ${id})`),
        );
      }, 10_000);

      this.pendingResolvers.set(id, (response) => {
        clearTimeout(timeout);
        resolve(response);
      });

      this.serverProcess.stdin.write(JSON.stringify(message) + "\n");
    });
  }

  /** Send a JSON-RPC notification (no response expected). */
  async sendNotification(method, params = {}) {
    const message = { jsonrpc: "2.0", method, params };
    this.serverProcess.stdin.write(JSON.stringify(message) + "\n");
    await new Promise((r) => setTimeout(r, 50));
  }

  /** Kill the server and clean up the temp directory. */
  async stop() {
    if (this.serverProcess) {
      this.serverProcess.kill("SIGTERM");
      this.serverProcess = null;
    }
    if (this.tmpDir) {
      rmSync(this.tmpDir, { recursive: true, force: true });
      this.tmpDir = null;
    }
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Parse the mock CLI's JSON from an MCP tools/call response. */
function parseMockResponse(mcpResponse) {
  assert.ok(mcpResponse.result, "Expected result in response");
  assert.ok(mcpResponse.result.content, "Expected content in result");
  assert.ok(
    mcpResponse.result.content.length > 0,
    "Expected at least one content item",
  );
  return JSON.parse(mcpResponse.result.content[0].text);
}

/** Extract just the _receivedArgs from a tools/call response. */
function getReceivedArgs(mcpResponse) {
  return parseMockResponse(mcpResponse)._receivedArgs;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe("MCP Server Integration Tests", () => {
  let client;

  before(async () => {
    client = new MCPTestClient();
    await client.start();
  });

  after(async () => {
    await client.stop();
  });

  // ── Protocol ──

  it("test_initialize", async () => {
    const response = await client.send("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "test-client", version: "1.0.0" },
    });

    assert.equal(response.jsonrpc, "2.0");
    assert.ok(response.result);
    assert.equal(response.result.protocolVersion, "2024-11-05");
    assert.deepStrictEqual(response.result.capabilities, { tools: {} });
    assert.equal(response.result.serverInfo.name, "homekit-automator");
    assert.equal(response.result.serverInfo.version, "1.1.0");

    // Send the initialized notification (no response expected)
    await client.sendNotification("notifications/initialized");
  });

  it("test_tools_list", async () => {
    const response = await client.send("tools/list");

    assert.ok(response.result);
    assert.ok(Array.isArray(response.result.tools));
    assert.equal(response.result.tools.length, 11);

    const toolNames = response.result.tools.map((t) => t.name).sort();
    const expected = [
      "automation_create",
      "automation_delete",
      "automation_edit",
      "automation_list",
      "automation_test",
      "device_control",
      "device_status",
      "energy_summary",
      "home_discover",
      "home_suggest",
      "scene_trigger",
    ];
    assert.deepStrictEqual(toolNames, expected);

    // Every tool must have the required MCP schema fields
    for (const tool of response.result.tools) {
      assert.ok(tool.name, "Tool must have a name");
      assert.ok(tool.description, "Tool must have a description");
      assert.ok(tool.inputSchema, "Tool must have an inputSchema");
      assert.equal(tool.inputSchema.type, "object");
    }
  });

  // ── Device Control Tools ──

  it("test_home_discover", async () => {
    const response = await client.send("tools/call", {
      name: "home_discover",
      arguments: {},
    });

    const args = getReceivedArgs(response);
    assert.equal(args[0], "discover");
    assert.ok(args.includes("--json"), "Should append --json flag");
    assert.equal(args.length, 2, "discover takes no extra args");
  });

  it("test_device_status", async () => {
    // With device parameter → CLI: get <device> --json
    const deviceResp = await client.send("tools/call", {
      name: "device_status",
      arguments: { device: "Kitchen Lights" },
    });
    const deviceArgs = getReceivedArgs(deviceResp);
    assert.equal(deviceArgs[0], "get");
    assert.equal(deviceArgs[1], "Kitchen Lights");
    assert.ok(deviceArgs.includes("--json"));

    // With room parameter → CLI: rooms --json  (Agent B's room-parameter fix)
    const roomResp = await client.send("tools/call", {
      name: "device_status",
      arguments: { room: "Kitchen" },
    });
    const roomArgs = getReceivedArgs(roomResp);
    assert.equal(roomArgs[0], "rooms", "Room query should use 'rooms' command");
    assert.ok(roomArgs.includes("--json"));
  });

  it("test_device_control", async () => {
    const response = await client.send("tools/call", {
      name: "device_control",
      arguments: {
        device: "Kitchen Lights",
        characteristic: "brightness",
        value: 75,
      },
    });

    const args = getReceivedArgs(response);
    assert.equal(args[0], "set");
    assert.equal(args[1], "Kitchen Lights");
    assert.equal(args[2], "brightness");
    assert.equal(args[3], "75"); // value is String()-ified by the server
    assert.ok(args.includes("--json"));
  });

  it("test_scene_trigger", async () => {
    const response = await client.send("tools/call", {
      name: "scene_trigger",
      arguments: { scene: "Good Night" },
    });

    const args = getReceivedArgs(response);
    assert.equal(args[0], "trigger");
    assert.equal(args[1], "Good Night");
    assert.ok(args.includes("--json"));
  });

  // ── Automation CRUD Tools ──

  it("test_automation_create", async () => {
    const definition = {
      name: "Morning Routine",
      trigger: {
        type: "schedule",
        humanReadable: "Every weekday at 6:45 AM",
        cron: "45 6 * * 1-5",
      },
      actions: [
        {
          deviceUuid: "uuid-kitchen-lights",
          deviceName: "Kitchen Lights",
          characteristic: "brightness",
          value: 60,
        },
      ],
    };

    const response = await client.send("tools/call", {
      name: "automation_create",
      arguments: definition,
    });

    const args = getReceivedArgs(response);
    assert.equal(args[0], "automation");
    assert.equal(args[1], "create");
    assert.equal(
      args[2],
      "--definition",
      "Must use --definition flag, not --json",
    );

    // The serialized definition is in args[3]
    const parsed = JSON.parse(args[3]);
    assert.equal(parsed.name, "Morning Routine");
    assert.equal(parsed.trigger.cron, "45 6 * * 1-5");
    assert.equal(parsed.actions.length, 1);
    assert.equal(parsed.actions[0].deviceName, "Kitchen Lights");

    // runCli still appends --json for output formatting
    assert.ok(args.includes("--json"));
  });

  it("test_automation_list", async () => {
    // Without filter
    const resp1 = await client.send("tools/call", {
      name: "automation_list",
      arguments: {},
    });
    const args1 = getReceivedArgs(resp1);
    assert.equal(args1[0], "automation");
    assert.equal(args1[1], "list");
    assert.ok(args1.includes("--json"));
    assert.ok(!args1.includes("--filter"), "No filter when omitted");

    // With filter
    const resp2 = await client.send("tools/call", {
      name: "automation_list",
      arguments: { filter: "enabled" },
    });
    const args2 = getReceivedArgs(resp2);
    assert.equal(args2[0], "automation");
    assert.equal(args2[1], "list");
    assert.ok(args2.includes("--filter"));
    assert.equal(args2[args2.indexOf("--filter") + 1], "enabled");
  });

  it("test_automation_edit", async () => {
    const response = await client.send("tools/call", {
      name: "automation_edit",
      arguments: {
        id: "auto-uuid-1",
        name: "Morning Routine",
        changes: { trigger: { cron: "15 7 * * 1-5" } },
      },
    });

    const args = getReceivedArgs(response);
    assert.equal(args[0], "automation");
    assert.equal(args[1], "edit");

    // Verify --id and --name flags
    assert.ok(args.includes("--id"));
    assert.equal(args[args.indexOf("--id") + 1], "auto-uuid-1");
    assert.ok(args.includes("--name"));
    assert.equal(args[args.indexOf("--name") + 1], "Morning Routine");

    // Verify --changes contains the serialized changes object
    assert.ok(args.includes("--changes"));
    const changes = JSON.parse(args[args.indexOf("--changes") + 1]);
    assert.equal(changes.trigger.cron, "15 7 * * 1-5");
  });

  it("test_automation_delete", async () => {
    const response = await client.send("tools/call", {
      name: "automation_delete",
      arguments: { id: "auto-uuid-1", name: "Morning Routine" },
    });

    const args = getReceivedArgs(response);
    assert.equal(args[0], "automation");
    assert.equal(args[1], "delete");
    assert.ok(args.includes("--force"), "MCP layer must always pass --force");
    assert.ok(args.includes("--id"));
    assert.equal(args[args.indexOf("--id") + 1], "auto-uuid-1");
    assert.ok(args.includes("--name"));
    assert.equal(args[args.indexOf("--name") + 1], "Morning Routine");
  });

  it("test_automation_test", async () => {
    // By name
    const resp1 = await client.send("tools/call", {
      name: "automation_test",
      arguments: { name: "Morning Routine" },
    });
    const args1 = getReceivedArgs(resp1);
    assert.equal(args1[0], "automation");
    assert.equal(args1[1], "test");
    assert.ok(args1.includes("--name"));
    assert.equal(args1[args1.indexOf("--name") + 1], "Morning Routine");

    // With ad-hoc actions
    const testActions = [
      {
        deviceUuid: "uuid-kitchen-lights",
        deviceName: "Kitchen Lights",
        characteristic: "power",
        value: true,
      },
    ];
    const resp2 = await client.send("tools/call", {
      name: "automation_test",
      arguments: { actions: testActions },
    });
    const args2 = getReceivedArgs(resp2);
    assert.equal(args2[0], "automation");
    assert.equal(args2[1], "test");
    assert.ok(args2.includes("--actions"));
    const parsed = JSON.parse(args2[args2.indexOf("--actions") + 1]);
    assert.equal(parsed.length, 1);
    assert.equal(parsed[0].deviceName, "Kitchen Lights");
    assert.equal(parsed[0].value, true);
  });

  // ── Intelligence Tools ──

  it("test_home_suggest", async () => {
    // Without focus
    const resp1 = await client.send("tools/call", {
      name: "home_suggest",
      arguments: {},
    });
    const args1 = getReceivedArgs(resp1);
    assert.equal(args1[0], "suggest");
    assert.ok(args1.includes("--json"));
    assert.ok(!args1.includes("--focus"), "No focus when omitted");

    // With focus
    const resp2 = await client.send("tools/call", {
      name: "home_suggest",
      arguments: { focus: "energy" },
    });
    const args2 = getReceivedArgs(resp2);
    assert.equal(args2[0], "suggest");
    assert.ok(args2.includes("--focus"));
    assert.equal(args2[args2.indexOf("--focus") + 1], "energy");
  });

  it("test_energy_summary", async () => {
    // Default (no period)
    const resp1 = await client.send("tools/call", {
      name: "energy_summary",
      arguments: {},
    });
    const args1 = getReceivedArgs(resp1);
    assert.equal(args1[0], "energy");
    assert.ok(!args1.includes("--period"), "No period when omitted");

    // With period
    const resp2 = await client.send("tools/call", {
      name: "energy_summary",
      arguments: { period: "month" },
    });
    const args2 = getReceivedArgs(resp2);
    assert.equal(args2[0], "energy");
    assert.ok(args2.includes("--period"));
    assert.equal(args2[args2.indexOf("--period") + 1], "month");
  });

  // ── Error Handling ──

  it("test_error_handling", async () => {
    // 1. Unknown tool → isError: true
    const unknownTool = await client.send("tools/call", {
      name: "nonexistent_tool",
      arguments: {},
    });
    assert.ok(unknownTool.result.isError, "Unknown tool should return isError");
    assert.ok(
      unknownTool.result.content[0].text.includes("Unknown tool"),
      "Error message should mention unknown tool",
    );

    // 2. Unknown method → JSON-RPC -32601 Method not found
    const unknownMethod = await client.send("unknown/method");
    assert.ok(
      unknownMethod.error,
      "Unknown method should return protocol error",
    );
    assert.equal(unknownMethod.error.code, -32601);

    // 3. device_status with neither device nor room → tool error
    const missingParams = await client.send("tools/call", {
      name: "device_status",
      arguments: {},
    });
    assert.ok(
      missingParams.result.isError,
      "Missing required params should return isError",
    );
    assert.ok(
      missingParams.result.content[0].text.includes("device or room"),
      "Error should mention the missing parameters",
    );
  });
});
