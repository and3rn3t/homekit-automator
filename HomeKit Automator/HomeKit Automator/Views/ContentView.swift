//
//  ContentView.swift
//  HomeKit Automator
//
//  Created by Matt on 2/26/26.
//

import SwiftUI

struct ContentView: View {
    @State private var store = AutomationStore()
    @State private var isLoading = false
    @State private var showingCreateSheet = false
    @State private var selectedAutomation: RegisteredAutomation?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedAutomation) {
                if isLoading {
                    ProgressView("Loading automations...")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if store.automations.isEmpty {
                    ContentUnavailableView {
                        Label("No Automations", systemImage: "sparkles")
                    } description: {
                        Text("Create your first automation to get started")
                    } actions: {
                        Button("Create Automation") {
                            createAutomation()
                        }
                        .accessibilityIdentifier(AccessibilityID.Content.emptyCreateButton)
                    }
                } else {
                    ForEach(store.automations) { automation in
                        NavigationLink(value: automation) {
                            AutomationRowView(automation: automation)
                        }
                    }
                    .onDelete(perform: deleteAutomations)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Content.sidebar)
            .navigationTitle("Automations")
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createAutomation) {
                        Label("Create Automation", systemImage: "plus")
                    }
                    .accessibilityIdentifier(AccessibilityID.Content.createButton)
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: refreshAutomations) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier(AccessibilityID.Content.refreshButton)
                }
            }
        } detail: {
            if let automation = selectedAutomation {
                AutomationDetailView(automation: automation, store: store)
            } else {
                ContentUnavailableView {
                    Label("Select an Automation", systemImage: "slider.horizontal.3")
                } description: {
                    Text("Choose an automation from the sidebar to view details")
                }
                .accessibilityIdentifier(AccessibilityID.Content.detailPlaceholder)
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateAutomationView {
                store.reload()
            }
        }
        .task {
            await loadAutomations()
        }
    }

    private func loadAutomations() async {
        isLoading = true
        defer { isLoading = false }

        // Small delay for UI feedback
        try? await Task.sleep(for: .seconds(0.3))

        // Reload from disk
        store.reload()
    }

    private func refreshAutomations() {
        Task {
            await loadAutomations()
        }
    }

    private func createAutomation() {
        showingCreateSheet = true
    }

    private func deleteAutomations(at offsets: IndexSet) {
        for index in offsets {
            let automation = store.automations[index]
            // Clear selection if we're deleting the selected item
            if selectedAutomation?.id == automation.id {
                selectedAutomation = nil
            }
            store.delete(automation.id)
        }
    }
}

// MARK: - Automation Row View

struct AutomationRowView: View {
    let automation: RegisteredAutomation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(automation.name)
                    .font(.headline)

                Spacer()

                if automation.enabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                } else {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
            }

            if let description = automation.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(automation.trigger.humanReadable)
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Automation Detail View

struct AutomationDetailView: View {
    let automation: RegisteredAutomation
    @Bindable var store: AutomationStore  // Use shared store instead of creating new one
    @State private var showingDeleteAlert = false
    @State private var isTriggeringManually = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Name", value: automation.name)

                if let description = automation.description {
                    LabeledContent("Description") {
                        Text(description)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Status") {
                    HStack {
                        Text(automation.enabled ? "Enabled" : "Disabled")
                            .foregroundStyle(automation.enabled ? .green : .secondary)

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { automation.enabled },
                                set: { _ in store.toggleEnabled(automation.id) }
                            )
                        )
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier(AccessibilityID.Detail.enableToggle)
                    }
                }

                LabeledContent("Shortcut", value: automation.shortcutName)
            }

            Section("Trigger") {
                LabeledContent("Type", value: automation.trigger.type)
                LabeledContent("Description") {
                    Text(automation.trigger.humanReadable)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                ForEach(Array(automation.actions.enumerated()), id: \.offset) { index, action in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Action \(index + 1)")
                            .font(.headline)

                        Text(action.deviceName)
                            .font(.subheadline)

                        Text("\(action.characteristic): \(action.value.displayString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if action.delaySeconds > 0 {
                            Text("Delay: \(action.delaySeconds)s")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let conditions = automation.conditions, !conditions.isEmpty {
                Section("Conditions") {
                    ForEach(Array(conditions.enumerated()), id: \.offset) { index, condition in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Condition \(index + 1)")
                                .font(.headline)

                            Text(condition.humanReadable)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("History") {
                LabeledContent("Created") {
                    Text(automation.createdAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastRun = automation.lastRun {
                    LabeledContent("Last Run") {
                        Text(lastRun)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                let successRate = store.successRate(for: automation.id)
                LabeledContent("Success Rate") {
                    Text(String(format: "%.0f%%", successRate))
                        .font(.caption)
                        .foregroundStyle(
                            successRate >= 90 ? .green : (successRate >= 50 ? .orange : .red)
                        )
                        .accessibilityIdentifier(AccessibilityID.Detail.successRate)
                }
            }

            Section {
                Button(action: triggerManually) {
                    if isTriggeringManually {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running...")
                    } else {
                        Label("Run Now", systemImage: "play.fill")
                    }
                }
                .disabled(isTriggeringManually)
                .accessibilityIdentifier(AccessibilityID.Detail.runNowButton)

                Button(role: .destructive, action: { showingDeleteAlert = true }) {
                    Label("Delete Automation", systemImage: "trash")
                }
                .accessibilityIdentifier(AccessibilityID.Detail.deleteButton)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(AccessibilityID.Detail.errorMessage)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(automation.name)
        .alert("Delete Automation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.delete(automation.id)
            }
        } message: {
            Text("Are you sure you want to delete \"\(automation.name)\"? This cannot be undone.")
        }
    }

    private func triggerManually() {
        Task {
            isTriggeringManually = true
            errorMessage = nil
            defer { isTriggeringManually = false }

            do {
                try await HelperAPIClient.shared.triggerAutomation(automation.id)
                // Give it a moment to execute
                try? await Task.sleep(for: .seconds(1))
                store.reload()
            } catch {
                errorMessage = "Failed to trigger: \(error.localizedDescription)"
                print("Failed to trigger automation: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}
#Preview("Automation Detail") {
    let store = AutomationStore()

    NavigationStack {
        AutomationDetailView(
            automation: RegisteredAutomation(
                id: "preview-1",
                name: "Morning Lights",
                description: "Turn on bedroom lights in the morning",
                trigger: AutomationTrigger(
                    type: "time",
                    humanReadable: "Every day at 7:00 AM"
                ),
                conditions: nil,
                actions: [
                    AutomationAction(
                        deviceName: "Bedroom Light",
                        characteristic: "On",
                        value: .bool(true)
                    )
                ],
                enabled: true,
                shortcutName: "Morning Lights",
                createdAt: "2026-02-26T08:00:00Z"
            ),
            store: store
        )
    }
}
