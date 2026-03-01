// CreateAutomationView.swift
// Sheet for creating a new automation using natural language input.
// The LLM processes the user's description and generates the automation definition.

import SwiftUI

struct CreateAutomationView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKeys.llmEnabled) private var llmEnabled: Bool = AppSettingsDefaults.llmEnabled

    @State private var userPrompt = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var loadingDeviceContext = false
    @State private var deviceContext: String?

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Automation")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(AccessibilityID.Create.title)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AccessibilityID.Create.cancelButton)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe Your Automation")
                        .font(.headline)

                    Text("Tell us what you want to automate in natural language. For example:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        exampleRow("Turn on the bedroom lights at 7 AM every weekday")
                        exampleRow("Turn off all lights at sunset")
                        exampleRow("When I arrive home, set thermostat to 72 degrees")
                        exampleRow("Dim living room lights to 30% at 9 PM")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                TextEditor(text: $userPrompt)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityIdentifier(AccessibilityID.Create.promptEditor)

                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier(AccessibilityID.Create.errorMessage)
                }

                if !llmEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LLM Integration Disabled")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Enable natural language automation in Settings → LLM")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier(AccessibilityID.Create.llmDisabledNotice)
                }

                Spacer()

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    if loadingDeviceContext {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading devices...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: createAutomation) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                            Text("Creating...")
                        } else {
                            Text("Create Automation")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating || !llmEnabled)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityID.Create.createButton)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 450)
        .task {
            await loadDeviceContext()
        }
        .alert("Automation Created", isPresented: $showSuccess) {
            Button("OK") {
                onComplete()
                dismiss()
            }
        } message: {
            Text("Your automation has been successfully created and registered.")
        }
    }

    private func exampleRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text("•")
            Text(text)
        }
    }

    private func createAutomation() {
        Task {
            isCreating = true
            errorMessage = nil

            defer { isCreating = false }

            do {
                // Check if LLM is enabled
                guard llmEnabled else {
                    errorMessage = "LLM integration is disabled. Enable it in Settings → LLM tab."
                    return
                }

                // Create LLM service
                guard let service = LLMService() else {
                    errorMessage = "LLM service not configured. Please set up your API key in Settings."
                    return
                }

                // Parse automation using LLM
                let definition = try await service.parseAutomation(
                    from: userPrompt,
                    deviceContext: deviceContext
                )

                // Send to helper to create automation
                let response = try await HelperAPIClient.shared.createAutomation(definition)

                if response.success {
                    showSuccess = true
                } else {
                    errorMessage = response.message ?? "Failed to create automation"
                }

            } catch LLMError.notConfigured {
                errorMessage = "Please configure your LLM API key in Settings → LLM tab"
            } catch LLMError.apiError(let code, let message) {
                errorMessage = "LLM API error (\(code)): \(message)"
            } catch LLMError.parsingFailed(let details) {
                errorMessage = "Failed to parse automation: \(details)"
            } catch {
                errorMessage = "Failed to create automation: \(error.localizedDescription)"
            }
        }
    }

    private func loadDeviceContext() async {
        loadingDeviceContext = true
        defer { loadingDeviceContext = false }

        do {
            deviceContext = try await LLMService.fetchDeviceContext()
        } catch {
            // Non-fatal: Continue without device context
            print("Could not load device context: \(error)")
            deviceContext = nil
        }
    }
}

// MARK: - Preview

#Preview {
    CreateAutomationView {
        print("Automation created")
    }
}
