# Security Policy

## Supported Versions

We actively support the latest major and minor versions of HomeKit Automator with security updates.

| Version | Supported          |
| ------- | ------------------ |
| 1.2.x   | :white_check_mark: |
| 1.1.x   | :white_check_mark: |
| 1.0.x   | :x:                |
| < 1.0   | :x:                |

## Security Considerations

HomeKit Automator integrates deeply with your smart home. Please be aware of the following:

### HomeKit Access
- The app requires full HomeKit access to control devices and create automations
- HomeKit data is processed locally on your Mac — we never transmit it to external servers
- The Unix domain socket (`~/Library/Application Support/homekit-automator/homekitauto.sock`) is restricted to your user account only (mode 0600)

### Apple Shortcuts Integration
- Automations are registered as Apple Shortcuts, which means they appear in the Shortcuts app
- Shortcuts run with your user permissions and can execute automation actions even when the main app is closed
- Shortcut names are prefixed with `HKA:` to distinguish them from user-created shortcuts

### AI Agent Access
- When used with OpenClaw or Claude Desktop, the AI agent has full control over your HomeKit devices via the MCP server
- The MCP server runs as a child process of the AI assistant and communicates with the CLI tool via standard input/output
- Consider your trust model carefully — AI agents can accidentally (or intentionally) trigger device actions

### File System Access
- Configuration and automation data is stored in `~/Library/Application Support/homekit-automator/`
- Files are readable/writable by your user account only
- No sensitive authentication tokens are stored (HomeKit uses native macOS APIs with iCloud authentication)

### Best Practices
- Review automations before confirming creation — verify device names, schedules, and actions
- Use the `automation_test` command to dry-run automations before registering them
- Regularly review registered Shortcuts in the Shortcuts app — delete any you no longer need
- Keep your macOS and Xcode versions up to date for the latest security patches
- Avoid running HomeKit Automator on shared or public machines

## Reporting a Vulnerability

If you discover a security vulnerability in HomeKit Automator, please report it privately:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Email the maintainer directly at: `and3rn3t` via GitHub (or open a draft security advisory)
3. Include:
   - A description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any suggested fixes (optional)

We aim to respond to security reports within 48 hours. If the vulnerability is confirmed, we will:

1. Develop and test a fix
2. Release a patch version as soon as possible
3. Credit you in the release notes (if desired)
4. Publish a security advisory on GitHub

Thank you for helping keep HomeKit Automator and its users safe!

## Security Updates

Security updates are announced via:
- GitHub Security Advisories
- Release notes in CHANGELOG.md
- GitHub Releases page

Subscribe to the repository to receive notifications about new releases and security updates.
