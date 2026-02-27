// LogEntryRow.swift
// Row component for the execution history timeline. Displays a single
// AutomationLogEntry with status icon, name, timestamp, and action summary.

import SwiftUI

struct LogEntryRow: View {
    let entry: AutomationLogEntry

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .font(.title3)
                .frame(width: 28)

            // Timeline connector
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
                Circle()
                    .fill(entry.isSuccess ? .green : .red)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
            }
            .frame(width: 8)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.automationName)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.quaternary)

                    Text(actionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errors = entry.errors, !errors.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(errors.prefix(3), id: \.self) { errorMsg in
                            Text(errorMsg)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                        if errors.count > 3 {
                            Text("+ \(errors.count - 3) more error(s)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Success rate badge
            Text(String(format: "%.0f%%", entry.successRate))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeColor.opacity(0.15))
                .foregroundStyle(badgeColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed

    private var statusIcon: some View {
        Group {
            if entry.isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if entry.succeeded > 0 {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var actionSummary: String {
        if entry.isSuccess {
            return "\(entry.actionsExecuted) action\(entry.actionsExecuted == 1 ? "" : "s") succeeded"
        } else {
            return "\(entry.succeeded)/\(entry.actionsExecuted) succeeded, \(entry.failed) failed"
        }
    }

    private var badgeColor: Color {
        if entry.successRate >= 90 { return .green }
        if entry.successRate >= 50 { return .orange }
        return .red
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var formattedTimestamp: String {
        guard let date = Self.isoFormatter.date(from: entry.timestamp) else {
            return entry.timestamp
        }
        return Self.displayFormatter.string(from: date)
    }
}
