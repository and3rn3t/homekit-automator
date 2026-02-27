#!/usr/bin/env node

/**
 * Mock homekitauto CLI for MCP server integration tests.
 *
 * This script simulates the `homekitauto` CLI binary. When the MCP server
 * calls `execFile("homekitauto", [...args])`, this mock receives the args
 * and returns a JSON response that includes:
 *
 *   - _mock: true          — flag so tests can confirm the mock was used
 *   - _receivedArgs: [...]  — the raw argv (so tests can verify CLI arg assembly)
 *   - Command-specific mock data so the server can parse a realistic response
 *
 * The test harness symlinks this file as "homekitauto" in a temp directory
 * and prepends that directory to PATH before spawning the MCP server.
 */

const args = process.argv.slice(2);
const command = args[0];

// Build a response that always includes the received args for verification
const response = {
  _mock: true,
  _receivedArgs: args,
  status: "ok",
};

// Strip --json from args for cleaner command parsing
const cleanArgs = args.filter((a) => a !== "--json");

switch (command) {
  // ── Device Control ──

  case "discover":
    response.homes = [
      {
        name: "My Home",
        rooms: [
          {
            name: "Kitchen",
            devices: [
              {
                name: "Kitchen Lights",
                uuid: "uuid-kitchen-lights",
                type: "lightbulb",
                characteristics: ["power", "brightness", "hue", "saturation"],
              },
              {
                name: "Coffee Maker",
                uuid: "uuid-coffee-maker",
                type: "outlet",
                characteristics: ["power"],
              },
            ],
          },
          {
            name: "Living Room",
            devices: [
              {
                name: "Living Room Lights",
                uuid: "uuid-lr-lights",
                type: "lightbulb",
                characteristics: ["power", "brightness"],
              },
              {
                name: "Smart TV",
                uuid: "uuid-tv",
                type: "television",
                characteristics: ["power", "active"],
              },
            ],
          },
          {
            name: "Bedroom",
            devices: [
              {
                name: "Bedroom Thermostat",
                uuid: "uuid-thermo",
                type: "thermostat",
                characteristics: [
                  "targetTemperature",
                  "hvacMode",
                  "currentTemperature",
                ],
              },
              {
                name: "Bedroom Light",
                uuid: "uuid-bed-light",
                type: "lightbulb",
                characteristics: ["power", "brightness"],
              },
            ],
          },
          {
            name: "Front Door",
            devices: [
              {
                name: "Front Door Lock",
                uuid: "uuid-lock",
                type: "lock",
                characteristics: ["lockState"],
              },
              {
                name: "Front Door Sensor",
                uuid: "uuid-sensor",
                type: "contactSensor",
                characteristics: ["contactState"],
              },
            ],
          },
        ],
        scenes: [
          { name: "Good Night", uuid: "uuid-scene-goodnight" },
          { name: "Good Morning", uuid: "uuid-scene-goodmorning" },
          { name: "Movie Time", uuid: "uuid-scene-movie" },
        ],
      },
    ];
    break;

  case "get":
    response.device = {
      name: cleanArgs[1] || "Unknown",
      uuid: "uuid-mock",
      state: { power: true, brightness: 75 },
    };
    break;

  case "rooms":
    response.rooms = [
      {
        name: "Kitchen",
        devices: [{ name: "Kitchen Lights", power: true, brightness: 100 }],
      },
      {
        name: "Living Room",
        devices: [{ name: "Living Room Lights", power: false }],
      },
      {
        name: "Bedroom",
        devices: [{ name: "Bedroom Thermostat", currentTemperature: 72 }],
      },
    ];
    break;

  case "set":
    response.result = {
      device: cleanArgs[1],
      characteristic: cleanArgs[2],
      value: cleanArgs[3],
      success: true,
    };
    break;

  case "batch-set": {
    const actionsIdx = cleanArgs.indexOf("--actions");
    const batchActions = actionsIdx >= 0 ? JSON.parse(cleanArgs[actionsIdx + 1]) : [];
    response.results = batchActions.map((a) => ({
      device: a.device,
      characteristic: a.characteristic,
      success: true,
    }));
    response.succeeded = batchActions.length;
    response.failed = 0;
    response.total = batchActions.length;
    break;
  }

  case "trigger":
    response.result = {
      scene: cleanArgs[1],
      triggered: true,
    };
    break;

  // ── Automation CRUD ──

  case "automation": {
    const subcommand = cleanArgs[1];
    switch (subcommand) {
      case "create":
        response.automation = {
          id: "auto-uuid-new",
          name: "New Automation",
          created: true,
        };
        break;
      case "list":
        response.automations = [
          {
            id: "auto-uuid-1",
            name: "Morning Routine",
            enabled: true,
            trigger: { type: "schedule", cron: "0 7 * * *" },
          },
          {
            id: "auto-uuid-2",
            name: "Bedtime",
            enabled: true,
            trigger: { type: "manual", keyword: "bedtime" },
          },
          {
            id: "auto-uuid-3",
            name: "Away Mode",
            enabled: false,
            trigger: { type: "manual", keyword: "away" },
          },
        ];
        break;
      case "edit":
        response.automation = { id: "auto-uuid-1", updated: true };
        break;
      case "delete":
        response.automation = { deleted: true };
        break;
      case "test":
        response.testResult = { actionsExecuted: 3, success: true };
        break;
      case "export":
        response.exported = 2;
        response.automations = [
          { id: "auto-uuid-1", name: "Morning Routine" },
          { id: "auto-uuid-2", name: "Bedtime" },
        ];
        break;
      case "import":
        response.imported = 1;
        response.updated = 0;
        response.skipped = 0;
        response.total = 1;
        break;
      default:
        process.stderr.write(`Unknown automation subcommand: ${subcommand}\n`);
        process.exit(1);
    }
    break;
  }

  // ── Intelligence ──

  case "suggest": {
    const focusIdx = cleanArgs.indexOf("--focus");
    response.suggestions = [
      {
        name: "Motion-triggered Lights",
        description: "Turn on hallway lights when motion detected",
        focus: focusIdx >= 0 ? cleanArgs[focusIdx + 1] : "convenience",
      },
      {
        name: "Night Cooling",
        description: "Lower thermostat at 10 PM",
        focus: "energy",
      },
    ];
    break;
  }

  case "energy": {
    const periodIdx = cleanArgs.indexOf("--period");
    response.summary = {
      period: periodIdx >= 0 ? cleanArgs[periodIdx + 1] : "week",
      devicesActive: 5,
      automationsRun: 12,
      estimatedSavings: "$4.50",
    };
    break;
  }

  case "intelligence": {
    // intelligence config [--default-home <name>] [--filter-mode <mode>] [--latitude <n>] [--longitude <n>] [--show] --json
    const configData = {};
    const dhIdx = cleanArgs.indexOf("--default-home");
    if (dhIdx >= 0) configData.defaultHome = cleanArgs[dhIdx + 1];
    const fmIdx = cleanArgs.indexOf("--filter-mode");
    if (fmIdx >= 0) configData.filterMode = cleanArgs[fmIdx + 1];
    const latIdx = cleanArgs.indexOf("--latitude");
    if (latIdx >= 0) configData.latitude = parseFloat(cleanArgs[latIdx + 1]);
    const lonIdx = cleanArgs.indexOf("--longitude");
    if (lonIdx >= 0) configData.longitude = parseFloat(cleanArgs[lonIdx + 1]);
    Object.assign(response, configData);
    break;
  }

  default:
    process.stderr.write(`Unknown command: ${command}\n`);
    process.exit(1);
}

process.stdout.write(JSON.stringify(response));
