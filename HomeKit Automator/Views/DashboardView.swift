// DashboardView.swift
// Main automation dashboard showing all registered automations with controls
// to enable/disable, delete, and inspect each one.

import SwiftUI

struct DashboardView: View {
    @State private var store = AutomationStore()
    @State private var searchText = ""
    @State private var deleteConfirmation: RegisteredAutomation?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Automations")
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

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search automations…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            if filteredAutomations.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredAutomations) { automation in
                        AutomationListItem(
                            automation: automation,
                            successRate: store.successRate(for: automation.id),
                            lastLogEntry: store.logEntries(for: automation.id).last,
                            onToggle: { store.toggleEnabled(automation.id) },
                            onDelete: { deleteConfirmation = automation }
                        )
                    }
                }
                .listStyle(.inset)
            }

            // Error bar
            if let error = store.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.red.opacity(0.1))
            }
        }
        .frame(minWidth: 500, minHeight: 300)
        .alert("Delete Automation",
               isPresented: Binding(
                   get: { deleteConfirmation != nil },
                   set: { if !$0 { deleteConfirmation = nil } }
               ),
               presenting: deleteConfirmation) { automation in
            Button("Delete", role: .destructive) {
                store.delete(automation.id)
                deleteConfirmation = nil
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmation = nil
            }
        } message: { automation in
            Text("Are you sure you want to delete \"\(automation.name)\"? This cannot be undone.")
        }
    }

    // MARK: - Computed

    private var filteredAutomations: [RegisteredAutomation] {
        if searchText.isEmpty {
            return store.automations
        }
        let query = searchText.lowercased()
        return store.automations.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false) ||
            $0.trigger.type.lowercased().contains(query)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "gearshape.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Automations")
                .font(.title3)
                .fontWeight(.medium)
            Text("Use the CLI or MCP tools to create automations.\nRun: homekitauto automation create --json '{…}'")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    DashboardView()
        .frame(width: 700, height: 500)
}
