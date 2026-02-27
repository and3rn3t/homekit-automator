//
//  ContentView.swift
//  HomeKit Automator
//
//  Created by Matt on 2/26/26.
//

import SwiftUI

struct ContentView: View {
    @State private var automations: [RegisteredAutomation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationSplitView {
            List {
                if isLoading {
                    ProgressView("Loading automations...")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if automations.isEmpty {
                    ContentUnavailableView {
                        Label("No Automations", systemImage: "sparkles")
                    } description: {
                        Text("Create your first automation to get started")
                    } actions: {
                        Button("Create Automation") {
                            createAutomation()
                        }
                    }
                } else {
                    ForEach(automations) { automation in
                        NavigationLink {
                            AutomationDetailView(automation: automation)
                        } label: {
                            AutomationRowView(automation: automation)
                        }
                    }
                }
            }
            .navigationTitle("Automations")
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createAutomation) {
                        Label("Create Automation", systemImage: "plus")
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: refreshAutomations) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        } detail: {
            ContentUnavailableView {
                Label("Select an Automation", systemImage: "slider.horizontal.3")
            } description: {
                Text("Choose an automation from the sidebar to view details")
            }
        }
        .task {
            await loadAutomations()
        }
    }
    
    private func loadAutomations() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Load automations from your HomeKit helper
        // For now, this is a placeholder
        try? await Task.sleep(for: .seconds(0.5))
        automations = []
    }
    
    private func refreshAutomations() {
        Task {
            await loadAutomations()
        }
    }
    
    private func createAutomation() {
        // TODO: Implement automation creation flow
        print("Create automation tapped")
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
                    Text(automation.enabled ? "Enabled" : "Disabled")
                        .foregroundStyle(automation.enabled ? .green : .secondary)
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
            }
        }
        .formStyle(.grouped)
        .navigationTitle(automation.name)
    }
}

#Preview {
    ContentView()
}
#Preview("Automation Detail") {
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
            )
        )
    }
}

