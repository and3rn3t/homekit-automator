// DebugView.swift
// Debug panel showing internal state and diagnostics for troubleshooting.
// Access via menu bar: Option+Click on status item (developer mode)

import SwiftUI

struct DebugView: View {
    @State private var store = AutomationStore()
    @State private var helperStatus: String = "Unknown"
    @State private var socketPath: String = SocketConstants.defaultPath
    @State private var automationCount: Int = 0
    @State private var logCount: Int = 0
    @State private var diskInfo: String = "Loading..."

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Debug Information")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(AccessibilityID.Debug.title)

                Spacer()

                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier(AccessibilityID.Debug.refreshButton)
            }
            .padding()

            Divider()

            // Content
            Form {
                Section("Application") {
                    LabeledContent("Bundle ID") {
                        Text(Bundle.main.bundleIdentifier ?? "Unknown")
                            .textSelection(.enabled)
                    }

                    LabeledContent("Version") {
                        Text(
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                                ?? "Unknown")
                    }

                    LabeledContent("Build") {
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                    }
                }

                Section("Helper Status") {
                    LabeledContent("Status") {
                        Text(helperStatus)
                            .foregroundStyle(helperStatus == "Running" ? .green : .red)
                            .accessibilityIdentifier(AccessibilityID.Debug.helperStatus)
                    }

                    LabeledContent("Socket Path") {
                        Text(socketPath)
                            .font(.caption)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(AccessibilityID.Debug.socketPath)
                    }

                    LabeledContent("Socket Exists") {
                        Text(FileManager.default.fileExists(atPath: socketPath) ? "Yes" : "No")
                            .foregroundStyle(
                                FileManager.default.fileExists(atPath: socketPath) ? .green : .red
                            )
                            .accessibilityIdentifier(AccessibilityID.Debug.socketExists)
                    }
                }

                Section("Data Store") {
                    LabeledContent("Automations") {
                        Text("\(automationCount)")
                            .accessibilityIdentifier(AccessibilityID.Debug.automationCount)
                    }

                    LabeledContent("Log Entries") {
                        Text("\(logCount)")
                            .accessibilityIdentifier(AccessibilityID.Debug.logCount)
                    }

                    LabeledContent("Config Directory") {
                        Text(store.configDir.path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    LabeledContent("Disk Usage") {
                        Text(diskInfo)
                            .font(.caption)
                    }
                }

                Section("System") {
                    LabeledContent("macOS Version") {
                        Text(ProcessInfo.processInfo.operatingSystemVersionString)
                    }

                    LabeledContent("Architecture") {
                        #if arch(arm64)
                            Text("Apple Silicon")
                        #elseif arch(x86_64)
                            Text("Intel")
                        #else
                            Text("Unknown")
                        #endif
                    }

                    LabeledContent("Memory Usage") {
                        Text(memoryUsage())
                    }
                }

                Section("File Paths") {
                    VStack(alignment: .leading, spacing: 8) {
                        PathRow(
                            label: "Automations",
                            path: store.configDir.appendingPathComponent("automations.json").path)
                        PathRow(
                            label: "Logs",
                            path: store.configDir.appendingPathComponent("logs/automation-log.json")
                                .path)
                        PathRow(label: "Socket", path: socketPath)
                    }
                }

                Section("Actions") {
                    Button("Test Socket Connection") {
                        testSocket()
                    }
                    .accessibilityIdentifier(AccessibilityID.Debug.testSocketButton)

                    Button("Open Config Directory") {
                        NSWorkspace.shared.open(store.configDir)
                    }
                    .accessibilityIdentifier(AccessibilityID.Debug.openConfigButton)

                    Button("Copy Diagnostics") {
                        copyDiagnostics()
                    }
                    .accessibilityIdentifier(AccessibilityID.Debug.copyDiagnosticsButton)

                    Button("Reset Token") {
                        SocketConstants.resetToken()
                        refresh()
                    }
                    .accessibilityIdentifier(AccessibilityID.Debug.resetTokenButton)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            refresh()
        }
    }

    // MARK: - Actions

    private func refresh() {
        store.reload()
        automationCount = store.automations.count
        logCount = store.logEntries.count

        Task {
            do {
                let status = try await HelperAPIClient.shared.getStatus()
                helperStatus = status.status == "ok" ? "Running" : "Error"
            } catch {
                helperStatus = "Not Running"
            }
        }

        calculateDiskUsage()
    }

    private func testSocket() {
        Task {
            do {
                let response = try await HelperAPIClient.shared.getStatus()
                let alert = NSAlert()
                alert.messageText = "Socket Test Successful"
                alert.informativeText =
                    "Status: \(response.status)\nVersion: \(response.version ?? "unknown")"
                alert.alertStyle = .informational
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Socket Test Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func copyDiagnostics() {
        let diagnostics = """
            HomeKit Automator Diagnostics
            ==============================

            Application:
            - Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")
            - Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            - Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")

            Helper Status:
            - Status: \(helperStatus)
            - Socket Path: \(socketPath)
            - Socket Exists: \(FileManager.default.fileExists(atPath: socketPath) ? "Yes" : "No")

            Data:
            - Automations: \(automationCount)
            - Log Entries: \(logCount)
            - Config Dir: \(store.configDir.path)
            - Disk Usage: \(diskInfo)

            System:
            - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            - Memory: \(memoryUsage())

            Generated: \(Date())
            """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Diagnostics Copied"
        alert.informativeText = "Debug information has been copied to the clipboard."
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: - Helpers

    private func calculateDiskUsage() {
        let fm = FileManager.default
        var totalSize: Int64 = 0

        if let enumerator = fm.enumerator(
            at: store.configDir, includingPropertiesForKeys: [.fileSizeKey])
        {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        diskInfo = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    private func memoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            return "Unknown"
        }

        return ByteCountFormatter.string(
            fromByteCount: Int64(info.resident_size), countStyle: .memory)
    }
}

// MARK: - Supporting Views

struct PathRow: View {
    let label: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(path)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)

                Spacer()

                Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
            }

            if FileManager.default.fileExists(atPath: path) {
                Label("Exists", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Label("Not Found", systemImage: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    DebugView()
}
