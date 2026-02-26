// AutomationListItem.swift
// Row component for the automation dashboard. Displays a single registered automation
// with its trigger icon, last run time, success badge, enable toggle, and delete button.

import SwiftUI

struct AutomationListItem: View {
    let automation: RegisteredAutomation
    let successRate: Double
    let lastLogEntry: AutomationLogEntry?
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Trigger type icon
            triggerIcon
                .font(.title2)
                .foregroundStyle(automation.enabled ? .accentColor : .secondary)
                .frame(width: 32)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(automation.name)
                    .fontWeight(.medium)
                    .foregroundStyle(automation.enabled ? .primary : .secondary)

                Text(automation.trigger.humanReadable)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let desc = automation.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Last run and status
            VStack(alignment: .trailing, spacing: 2) {
                if let entry = lastLogEntry {
                    statusBadge(for: entry)
                    Text(formattedDate(entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never run")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !store_logEntries_empty {
                    Text(String(format: "%.0f%% success", successRate))
                        .font(.caption2)
                        .foregroundStyle(successRate >= 90 ? .green : (successRate >= 50 ? .orange : .red))
                }
            }

            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { automation.enabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(automation.enabled ? "Disable automation" : "Enable automation")

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete automation")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private var triggerIcon: some View {
        Group {
            switch automation.trigger.type {
            case "schedule":
                Image(systemName: "clock.fill")
            case "solar":
                Image(systemName: "sun.horizon.fill")
            case "manual":
                Image(systemName: "hand.tap.fill")
            case "device_state":
                Image(systemName: "sensor.fill")
            default:
                Image(systemName: "questionmark.circle")
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for entry: AutomationLogEntry) -> some View {
        if entry.isSuccess {
            Label("Success", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("\(entry.failed) failed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Helpers

    /// Whether there are any log entries for this automation (used to decide if success rate is shown).
    private var store_logEntries_empty: Bool {
        lastLogEntry != nil
    }

    private func formattedDate(_ iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso8601) else { return iso8601 }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
