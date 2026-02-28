// CreateAutomationView.swift
// Sheet for creating a new automation using natural language input.
// The LLM processes the user's description and generates the automation definition.

import SwiftUI

struct CreateAutomationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userPrompt = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Automation")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
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
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
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
                    .disabled(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 400)
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
                // This is a simplified version. In a real implementation, you would:
                // 1. Send the user prompt to your LLM service
                // 2. Parse the response into an AutomationDefinition
                // 3. Send it to the helper via HelperAPIClient
                
                // For now, we'll show an error indicating this needs LLM integration
                throw CreateAutomationError.notImplemented
                
                // Example of what the full implementation would look like:
                // let definition = try await generateAutomationDefinition(from: userPrompt)
                // let response = try await HelperAPIClient.shared.createAutomation(definition)
                // if response.success {
                //     showSuccess = true
                // } else {
                //     errorMessage = response.message ?? "Failed to create automation"
                // }
                
            } catch CreateAutomationError.notImplemented {
                errorMessage = """
                Automation creation requires integration with an LLM service (OpenAI, Claude, etc.) \
                to parse natural language into automation definitions.
                
                For now, please use the CLI tool:
                homekitauto automation create --interactive
                """
            } catch {
                errorMessage = "Failed to create automation: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Errors

enum CreateAutomationError: LocalizedError {
    case notImplemented
    case llmServiceUnavailable
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "LLM integration not implemented"
        case .llmServiceUnavailable:
            return "LLM service is unavailable"
        case .invalidResponse:
            return "Invalid response from LLM service"
        }
    }
}

// MARK: - Preview

#Preview {
    CreateAutomationView {
        print("Automation created")
    }
}
