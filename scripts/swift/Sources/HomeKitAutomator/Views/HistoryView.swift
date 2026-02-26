// HistoryView.swift
// Execution history view showing a filterable, sortable timeline of automation runs.

import SwiftUI

struct HistoryView: View {
    @State private var store = AutomationStore()
    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var sortOrder: SortOrder = .newestFirst

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Execution History")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { store.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh from disk")
            }
            .padding()

            Divider()

            // Filters
            filtersBar

            Divider()

            // Summary
            if !filteredEntries.isEmpty {
                summaryBar
                Divider()
            }

            // Content
            if filteredEntries.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Filters Bar

    private var filtersBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by name…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 200)

            // Status filter
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Spacer()

            // Date range
            DatePicker("From", selection: $startDate, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: 120)

            Text("–")
                .foregroundStyle(.secondary)

            DatePicker("To", selection: $endDate, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: 120)

            // Sort order
            Button(action: { sortOrder.toggle() }) {
                Image(systemName: sortOrder == .newestFirst ? "arrow.down" : "arrow.up")
            }
            .help(sortOrder == .newestFirst ? "Newest first" : "Oldest first")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            Label("\(filteredEntries.count) entries", systemImage: "list.bullet")
                .font(.caption)
                .foregroundStyle(.secondary)

            let successCount = filteredEntries.filter(\.isSuccess).count
            let failCount = filteredEntries.count - successCount
            let rate = filteredEntries.isEmpty ? 100.0 :
                Double(successCount) / Double(filteredEntries.count) * 100.0

            Label("\(successCount) succeeded", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)

            if failCount > 0 {
                Label("\(failCount) failed", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Label(String(format: "%.0f%% success rate", rate), systemImage: "chart.pie")
                .font(.caption)
                .foregroundStyle(rate >= 90 ? .green : (rate >= 50 ? .orange : .red))

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Execution History")
                .font(.title3)
                .fontWeight(.medium)
            Text("Automation execution logs will appear here\nonce automations have been run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Filtered & Sorted

    private static let isoFormatter = ISO8601DateFormatter()

    private var filteredEntries: [AutomationLogEntry] {
        let isoFormatter = Self.isoFormatter

        var result = store.logEntries

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.automationName.lowercased().contains(query) }
        }

        // Status filter
        switch statusFilter {
        case .all:
            break
        case .success:
            result = result.filter { $0.isSuccess }
        case .failure:
            result = result.filter { !$0.isSuccess }
        }

        // Date range filter
        result = result.filter { entry in
            guard let date = isoFormatter.date(from: entry.timestamp) else { return true }
            return date >= startDate && date <= endDate
        }

        // Sort
        result.sort { a, b in
            let dateA = isoFormatter.date(from: a.timestamp) ?? .distantPast
            let dateB = isoFormatter.date(from: b.timestamp) ?? .distantPast
            return sortOrder == .newestFirst ? dateA > dateB : dateA < dateB
        }

        return result
    }
}

// MARK: - Supporting Types

enum StatusFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case failure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .success: return "Success"
        case .failure: return "Failed"
        }
    }
}

enum SortOrder {
    case newestFirst
    case oldestFirst

    mutating func toggle() {
        self = (self == .newestFirst) ? .oldestFirst : .newestFirst
    }
}

#Preview {
    HistoryView()
        .frame(width: 700, height: 500)
}
