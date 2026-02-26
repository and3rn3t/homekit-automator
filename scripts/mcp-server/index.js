#!/usr/bin/env node

/**
 * HomeKit Automator MCP Server
 *
 * Stdio-based MCP server implementing the Model Context Protocol (version 2024-11-05)
 * that bridges AI agents to Apple HomeKit via the `homekitauto` CLI tool.
 *
 * Architecture:
 *   AI Agent ↔ MCP (stdin/stdout JSON-RPC) ↔ this server ↔ homekitauto CLI ↔ HomeKitHelper ↔ Apple HomeKit
 *
 * The server is intentionally thin — it translates MCP tool calls into CLI invocations
 * and returns the JSON output. All HomeKit logic lives in the Swift CLI and Catalyst helper.
 * This design keeps the MCP layer zero-dependency (no npm packages required) and makes
 * it easy to test tools independently via the CLI.
 *
 * Exposes 11 tools across three categories:
 *   - Device control:  home_discover, device_status, device_control, scene_trigger
 *   - Automation CRUD: automation_create, automation_list, automation_edit, automation_delete, automation_test
 *   - Intelligence:    home_suggest, energy_summary
 *
 * Usage:
 *   node index.js                    # Start the MCP server (reads stdin, writes stdout)
 *   echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node index.js  # Quick test
 *
 * Requirements:
 *   - Node.js >= 20 (ES modules)
 *   - `homekitauto` CLI on PATH (built from scripts/swift/)
 *   - HomeKit Automator helper app running (provides the HomeKit bridge)
 *
 * Protocol: Each line on stdin is a JSON-RPC 2.0 message. Responses are written
 * as single-line JSON to stdout. Diagnostic messages go to stderr.
 */

import { execFile, execFileSync } from "node:child_process"; // Spawns the CLI as a child process
import { promisify } from "node:util";          // Converts callback-based execFile to async/await
import { createInterface } from "node:readline"; // Reads stdin line-by-line for JSON-RPC messages
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const exec = promisify(execFile);

// ─── Version & Configuration ─────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(readFileSync(join(__dirname, 'package.json'), 'utf8'));
const VERSION = pkg.version;

/** CLI timeout in ms. Override with HOMEKITAUTO_TIMEOUT env var. Default: 60s. */
const CLI_TIMEOUT = parseInt(process.env.HOMEKITAUTO_TIMEOUT || '60000', 10);

/** Track active CLI child processes for graceful shutdown. */
const activeProcesses = new Set();

/** Path to the homekitauto CLI binary. Must be on $PATH or an absolute path. */
const CLI = "homekitauto";

// ─── Tool Definitions ────────────────────────────────────────────────────────
//
// Each tool is defined with a name, description, and JSON Schema inputSchema
// per the MCP specification. The descriptions are written to help the LLM
// understand when and how to call each tool. The schemas are intentionally
// permissive (few required fields) to let the LLM fill in what it can from
// natural language, while the CLI validates strictly before acting.

const TOOLS = [
  {
    name: "home_discover",
    description:
      "Discover all HomeKit homes, rooms, devices, and their capabilities. " +
      "Call this first in any new conversation about the user's home.",
    inputSchema: {
      type: "object",
      properties: {
        home: {
          type: "string",
          description: "Filter discovery to a specific home name",
        },
      },
    },
  },
  {
    name: "device_status",
    description: "Get the current state of a specific device or all devices in a room.",
    inputSchema: {
      type: "object",
      properties: {
        device: {
          type: "string",
          description: "Device name or UUID",
        },
        room: {
          type: "string",
          description: "Room name (returns all devices in room)",
        },
        home: {
          type: "string",
          description: "Home name to scope the lookup",
        },
      },
    },
  },
  {
    name: "device_control",
    description: "Send an immediate control command to a device.",
    inputSchema: {
      type: "object",
      properties: {
        device: {
          type: "string",
          description: "Device name or UUID",
        },
        characteristic: {
          type: "string",
          description:
            "What to change: power, brightness, hue, saturation, colorTemperature, " +
            "targetTemperature, hvacMode, lockState, targetPosition, active, rotationSpeed, etc.",
        },
        value: {
          description:
            "Target value: true/false for power/locks, 0-100 for brightness/position, " +
            "number for temperature, string for modes",
        },
        home: {
          type: "string",
          description: "Home name to scope the device lookup",
        },
      },
      required: ["device", "characteristic", "value"],
    },
  },
  {
    name: "scene_trigger",
    description: "Activate an Apple Home scene.",
    inputSchema: {
      type: "object",
      properties: {
        scene: {
          type: "string",
          description: "Scene name or UUID",
        },
        home: {
          type: "string",
          description: "Home name to scope the scene lookup",
        },
      },
      required: ["scene"],
    },
  },
  {
    name: "automation_create",
    description:
      "Create a new home automation and register it as an Apple Shortcut. " +
      "The automation will run on the specified schedule without needing the AI agent.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Human-readable automation name" },
        trigger: {
          type: "object",
          description: "When the automation fires",
          properties: {
            type: {
              type: "string",
              enum: ["schedule", "solar", "manual", "device_state"],
            },
            humanReadable: { type: "string" },
            cron: { type: "string" },
            timezone: { type: "string" },
            event: { type: "string" },
            offsetMinutes: { type: "number" },
            keyword: { type: "string" },
            deviceUuid: { type: "string" },
            deviceName: { type: "string" },
            characteristic: { type: "string" },
            operator: { type: "string" },
            value: {},
          },
          required: ["type", "humanReadable"],
        },
        conditions: {
          type: "array",
          description: "Optional guards that must be true for automation to run",
          items: { type: "object" },
        },
        actions: {
          type: "array",
          description: "Ordered list of device actions",
          items: {
            type: "object",
            properties: {
              deviceUuid: { type: "string" },
              deviceName: { type: "string" },
              room: { type: "string" },
              characteristic: { type: "string" },
              value: {},
              delaySeconds: { type: "number" },
              type: { type: "string" },
              sceneName: { type: "string" },
              sceneUuid: { type: "string" },
            },
            required: ["deviceUuid", "deviceName", "characteristic", "value"],
          },
        },
        enabled: { type: "boolean", default: true },
      },
      required: ["name", "trigger", "actions"],
    },
  },
  {
    name: "automation_list",
    description: "List all registered home automations.",
    inputSchema: {
      type: "object",
      properties: {
        filter: {
          type: "string",
          enum: ["enabled", "disabled", "schedule", "manual"],
          description: "Optional filter",
        },
      },
    },
  },
  {
    name: "automation_edit",
    description: "Modify an existing automation.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Automation UUID" },
        name: { type: "string", description: "Automation name (alternative to id)" },
        changes: {
          type: "object",
          description: "Partial automation object with fields to update",
        },
      },
      required: ["changes"],
    },
  },
  {
    name: "automation_delete",
    description: "Delete an automation and its Apple Shortcut.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Automation UUID" },
        name: { type: "string", description: "Automation name" },
      },
    },
  },
  {
    name: "automation_test",
    description:
      "Dry-run an automation — execute all its device actions immediately without scheduling.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Automation UUID" },
        name: { type: "string", description: "Automation name" },
        actions: {
          type: "array",
          description: "Or provide raw actions to test ad-hoc",
          items: { type: "object" },
        },
      },
    },
  },
  {
    name: "home_suggest",
    description:
      "Analyze the user's home setup and suggest useful automations they haven't created yet.",
    inputSchema: {
      type: "object",
      properties: {
        focus: {
          type: "string",
          enum: ["energy", "security", "comfort", "convenience"],
          description: "Narrow suggestions to a specific focus area",
        },
      },
    },
  },
  {
    name: "energy_summary",
    description: "Get insights about device usage patterns and automation activity.",
    inputSchema: {
      type: "object",
      properties: {
        period: {
          type: "string",
          enum: ["today", "week", "month"],
          default: "week",
        },
      },
    },
  },
];

// ─── CLI Execution ───────────────────────────────────────────────────────────

/**
 * Execute the homekitauto CLI with the given arguments.
 *
 * Automatically appends `--json` to every invocation so that the CLI returns
 * machine-readable JSON output. The 30-second timeout covers the worst case
 * of a full home discovery with many accessories.
 *
 * @param {string[]} args - CLI arguments (e.g., ["discover"] or ["set", "Kitchen Lights", "power", "true"])
 * @returns {string} The trimmed stdout from the CLI (always JSON)
 * @throws {Error} If the CLI exits non-zero or times out
 */
async function runCli(args) {
  let child;
  try {
    const childPromise = exec(CLI, [...args, "--json"], {
      timeout: CLI_TIMEOUT,
    });
    child = childPromise.child;
    activeProcesses.add(child);
    const { stdout, stderr } = await childPromise;
    if (stderr) {
      console.error(`[MCP] CLI stderr: ${stderr}`);
    }
    return stdout.trim();
  } catch (error) {
    throw new Error(
      `CLI error: ${error.stderr || error.message}`
    );
  } finally {
    if (child) activeProcesses.delete(child);
  }
}

// ─── Tool Handlers ───────────────────────────────────────────────────────────

/**
 * Map an MCP tool call to the corresponding CLI invocation.
 *
 * Each case translates tool parameters into CLI arguments. The mapping is
 * intentionally straightforward: most tools map 1:1 to a CLI subcommand.
 * Complex parameters (like automation definitions) are JSON-stringified
 * and passed via --json flags.
 *
 * @param {string} name - MCP tool name (e.g., "home_discover", "device_control")
 * @param {object} args - Tool arguments from the LLM
 * @returns {string} JSON string result from the CLI
 * @throws {Error} If the tool name is unknown or the CLI fails
 */
async function handleTool(name, args) {
  validateArgs(name, args);

  switch (name) {
    // ── Device Control Tools ──

    case "home_discover": {
      // Maps to: homekitauto discover [--home <name>] --json
      const discoverArgs = ["discover"];
      if (args.home) discoverArgs.push("--home", args.home);
      return await runCli(discoverArgs);
    }

    case "device_status": {
      // Maps to: homekitauto get <device> [--home <name>] --json  OR  homekitauto rooms [--home <name>] --json
      const statusArgs = [];
      if (args.device) {
        statusArgs.push("get", args.device);
      } else if (args.room) {
        statusArgs.push("rooms");
      } else {
        throw new Error("Provide either device or room parameter");
      }
      if (args.home) statusArgs.push("--home", args.home);
      return await runCli(statusArgs);
    }

    case "device_control": {
      // Maps to: homekitauto set <device> <characteristic> <value> [--home <name>] --json
      const controlArgs = ["set", args.device, args.characteristic, String(args.value)];
      if (args.home) controlArgs.push("--home", args.home);
      return await runCli(controlArgs);
    }

    case "scene_trigger": {
      // Maps to: homekitauto trigger <scene> [--home <name>] --json
      const triggerArgs = ["trigger", args.scene];
      if (args.home) triggerArgs.push("--home", args.home);
      return await runCli(triggerArgs);
    }

    // ── Automation CRUD Tools ──

    case "automation_create":
      // Maps to: homekitauto automation create --definition '<full automation definition>'
      // The entire args object (name, trigger, conditions, actions) is serialized as JSON
      return await runCli([
        "automation",
        "create",
        "--definition",
        JSON.stringify(args),
      ]);

    case "automation_list": {
      // Maps to: homekitauto automation list [--filter <type>] --json
      const cliArgs = ["automation", "list"];
      if (args.filter) cliArgs.push("--filter", args.filter);
      return await runCli(cliArgs);
    }

    case "automation_edit": {
      // Maps to: homekitauto automation edit [--id <uuid>] [--name <name>] --changes '<json>'
      const editArgs = ["automation", "edit"];
      if (args.id) editArgs.push("--id", args.id);
      if (args.name) editArgs.push("--name", args.name);
      editArgs.push("--changes", JSON.stringify(args.changes));
      return await runCli(editArgs);
    }

    case "automation_delete": {
      // Maps to: homekitauto automation delete --force [--id <uuid>] [--name <name>]
      // Always uses --force since the MCP layer doesn't support interactive prompts
      const deleteArgs = ["automation", "delete", "--force"];
      if (args.id) deleteArgs.push("--id", args.id);
      if (args.name) deleteArgs.push("--name", args.name);
      return await runCli(deleteArgs);
    }

    case "automation_test": {
      // Maps to: homekitauto automation test [--id <uuid>] [--name <name>] [--actions '<json>']
      // Executes actions immediately for verification without scheduling
      const testArgs = ["automation", "test"];
      if (args.id) testArgs.push("--id", args.id);
      if (args.name) testArgs.push("--name", args.name);
      if (args.actions) testArgs.push("--actions", JSON.stringify(args.actions));
      return await runCli(testArgs);
    }

    // ── Intelligence Tools ──

    case "home_suggest": {
      // Maps to: homekitauto suggest [--focus <category>] --json
      const suggestArgs = ["suggest"];
      if (args.focus) suggestArgs.push("--focus", args.focus);
      return await runCli(suggestArgs);
    }

    case "energy_summary": {
      // Maps to: homekitauto energy [--period <today|week|month>] --json
      const energyArgs = ["energy"];
      if (args.period) energyArgs.push("--period", args.period);
      return await runCli(energyArgs);
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// ─── MCP Protocol ────────────────────────────────────────────────────────────
//
// Implements the MCP transport layer over stdio. Each line from stdin is a
// complete JSON-RPC 2.0 message. Responses are written to stdout as single-line
// JSON followed by a newline. Diagnostic logging goes to stderr so it doesn't
// interfere with the protocol.
//
// Supported methods:
//   - initialize:              Returns server capabilities and version info
//   - notifications/initialized: Acknowledgement (no response)
//   - tools/list:              Returns the TOOLS array with schemas
//   - tools/call:              Dispatches to handleTool() and wraps the result

// ─── Input Validation ────────────────────────────────────────────────────────

/**
 * Validate that required arguments are present for a given tool.
 *
 * @param {string} toolName - The MCP tool name
 * @param {object} args - The arguments provided by the caller
 * @throws {Error} If a required parameter is missing
 */
function validateArgs(toolName, args) {
  const required = {
    'device_status': [],
    'device_control': ['device', 'characteristic', 'value'],
    'scene_trigger': ['scene'],
    'automation_create': ['name', 'trigger', 'actions'],
    'automation_edit': ['changes'],
    'automation_delete': [],
    'automation_test': [],
    'home_discover': [],
    'home_suggest': [],
    'automation_list': [],
    'energy_summary': []
  };
  const reqs = required[toolName] || [];
  for (const param of reqs) {
    if (args[param] === undefined || args[param] === null) {
      throw new Error(`Missing required parameter: ${param}`);
    }
  }
}

/** Read stdin line-by-line. Each line is a complete JSON-RPC message. */
const rl = createInterface({ input: process.stdin });

rl.on("line", async (line) => {
  try {
    const message = JSON.parse(line);
    const response = await handleMessage(message);
    if (response) {
      process.stdout.write(JSON.stringify(response) + "\n");
    }
  } catch (error) {
    const errorResponse = {
      jsonrpc: "2.0",
      id: null,
      error: { code: -32700, message: "Parse error" },
    };
    process.stdout.write(JSON.stringify(errorResponse) + "\n");
  }
});

/**
 * Handle a single MCP JSON-RPC message and return the response object.
 *
 * Returns null for notifications (which don't expect a response).
 * Returns a JSON-RPC error for unknown methods (-32601 Method Not Found).
 * Tool call errors are returned as successful responses with isError: true,
 * per the MCP spec (tool errors are not protocol errors).
 *
 * @param {object} message - Parsed JSON-RPC 2.0 message with id, method, params
 * @returns {object|null} JSON-RPC response or null for notifications
 */
async function handleMessage(message) {
  const { id, method, params } = message;

  switch (method) {
    case "initialize":
      // Validate CLI binary is available before reporting server capabilities
      try {
        execFileSync(CLI, ["--help"], { timeout: 5000, stdio: 'pipe' });
      } catch {
        process.stderr.write(`[HomeKit Automator MCP] WARNING: CLI binary '${CLI}' not found or not executable. Tool calls will fail.\n`);
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: {
            tools: {},
          },
          serverInfo: {
            name: "homekit-automator",
            version: VERSION,
          },
        },
      };

    case "notifications/initialized":
      return null; // No response needed

    case "ping":
      return { jsonrpc: "2.0", id, result: {} };

    case "tools/list":
      return {
        jsonrpc: "2.0",
        id,
        result: { tools: TOOLS },
      };

    case "tools/call": {
      const { name, arguments: args } = params;
      try {
        const result = await handleTool(name, args || {});
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [
              {
                type: "text",
                text: result,
              },
            ],
          },
        };
      } catch (error) {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [
              {
                type: "text",
                text: `Error: ${error.message}`,
              },
            ],
            isError: true,
          },
        };
      }
    }

    default:
      return {
        jsonrpc: "2.0",
        id,
        error: { code: -32601, message: `Method not found: ${method}` },
      };
  }
}

// ─── Graceful Shutdown ────────────────────────────────────────────────────────

function shutdown() {
  for (const child of activeProcesses) {
    child.kill('SIGTERM');
  }
  process.exit(0);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

process.stderr.write("[HomeKit Automator MCP] Server started\n");
