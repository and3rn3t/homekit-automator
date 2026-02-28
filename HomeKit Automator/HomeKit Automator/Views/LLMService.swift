// LLMService.swift
// Service for parsing natural language into AutomationDefinition using LLM APIs.
// Supports OpenAI, Claude, and custom endpoints.

import Foundation

/// Service for converting natural language descriptions into structured automation definitions.
@MainActor
final class LLMService {
    
    // MARK: - Properties
    
    private let provider: LLMProvider
    private let apiKey: String
    private let model: String
    private let endpoint: String
    private let timeout: TimeInterval
    
    // MARK: - Init
    
    init(provider: LLMProvider, apiKey: String, model: String? = nil, endpoint: String? = nil, timeout: TimeInterval = 30) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model?.isEmpty == false ? model! : provider.defaultModel
        self.endpoint = endpoint?.isEmpty == false ? endpoint! : provider.defaultEndpoint
        self.timeout = timeout
    }
    
    /// Convenience initializer that reads from UserDefaults
    convenience init?() {
        let providerRaw = UserDefaults.standard.string(forKey: AppSettingsKeys.llmProvider) ?? AppSettingsDefaults.llmProvider
        guard let provider = LLMProvider(rawValue: providerRaw) else { return nil }
        
        let apiKey = UserDefaults.standard.string(forKey: AppSettingsKeys.llmAPIKey) ?? AppSettingsDefaults.llmAPIKey
        guard !apiKey.isEmpty else { return nil }
        
        let model = UserDefaults.standard.string(forKey: AppSettingsKeys.llmModel) ?? AppSettingsDefaults.llmModel
        let endpoint = UserDefaults.standard.string(forKey: AppSettingsKeys.llmEndpoint) ?? AppSettingsDefaults.llmEndpoint
        let timeout = TimeInterval(UserDefaults.standard.integer(forKey: AppSettingsKeys.llmTimeout))
        
        self.init(
            provider: provider,
            apiKey: apiKey,
            model: model.isEmpty ? nil : model,
            endpoint: endpoint.isEmpty ? nil : endpoint,
            timeout: timeout > 0 ? timeout : 30
        )
    }
    
    // MARK: - Main API
    
    /// Parses a natural language description into an AutomationDefinition.
    /// - Parameter prompt: Natural language description of the automation
    /// - Parameter deviceContext: Optional device map context for better parsing
    /// - Returns: Parsed automation definition
    func parseAutomation(from prompt: String, deviceContext: String? = nil) async throws -> AutomationDefinition {
        let systemPrompt = buildSystemPrompt(deviceContext: deviceContext)
        let userPrompt = buildUserPrompt(from: prompt)
        
        let response = try await sendRequest(system: systemPrompt, user: userPrompt)
        let definition = try parseResponse(response)
        
        return definition
    }
    
    // MARK: - Prompt Engineering
    
    private func buildSystemPrompt(deviceContext: String?) -> String {
        var prompt = """
        You are an expert HomeKit automation assistant. Your job is to convert natural language descriptions into structured JSON automation definitions.
        
        IMPORTANT: Respond with ONLY valid JSON. Do not include markdown code blocks, explanations, or any text outside the JSON object.
        
        Output format (JSON only, no markdown):
        {
          "name": "Brief automation name",
          "description": "Detailed description",
          "trigger": {
            "type": "schedule|solar|manual|device_state",
            "humanReadable": "Human description",
            "cron": "cron expression (if schedule)",
            "timezone": "timezone (if schedule)",
            "event": "sunrise|sunset (if solar)",
            "offsetMinutes": offset (if solar),
            "keyword": "keyword (if manual)",
            "deviceName": "device name (if device_state)",
            "characteristic": "characteristic (if device_state)",
            "operator": "equals|above|below (if device_state)",
            "value": value (if device_state)
          },
          "conditions": [
            {
              "type": "time|device_state|location",
              "humanReadable": "Human description",
              // ... condition-specific fields
            }
          ],
          "actions": [
            {
              "deviceName": "Device name",
              "characteristic": "On|Brightness|Temperature|etc",
              "value": value,
              "delaySeconds": 0
            }
          ],
          "enabled": true
        }
        
        Trigger types:
        - "schedule": Time-based (use cron, timezone)
        - "solar": Sunrise/sunset (use event, offsetMinutes)
        - "manual": Shortcut/voice (use keyword)
        - "device_state": Device change (use deviceName, characteristic, operator, value)
        
        Common characteristics:
        - "On": true/false
        - "Brightness": 0-100
        - "Temperature": degrees
        - "Hue": 0-360
        - "Saturation": 0-100
        
        Cron format: "minute hour day month weekday"
        - "0 7 * * *" = 7:00 AM daily
        - "0 7 * * 1-5" = 7:00 AM weekdays
        - "0 22 * * 0,6" = 10:00 PM weekends
        
        Examples:
        
        Input: "Turn on bedroom lights at 7 AM every weekday"
        Output:
        {
          "name": "Morning Lights",
          "description": "Turn on bedroom lights at 7 AM on weekdays",
          "trigger": {
            "type": "schedule",
            "humanReadable": "Every weekday at 7:00 AM",
            "cron": "0 7 * * 1-5",
            "timezone": "America/Los_Angeles"
          },
          "conditions": null,
          "actions": [
            {
              "deviceName": "Bedroom Light",
              "characteristic": "On",
              "value": true,
              "delaySeconds": 0
            }
          ],
          "enabled": true
        }
        
        Input: "Dim living room lights to 30% at sunset"
        Output:
        {
          "name": "Evening Dimming",
          "description": "Dim living room lights to 30% at sunset",
          "trigger": {
            "type": "solar",
            "humanReadable": "At sunset",
            "event": "sunset",
            "offsetMinutes": 0
          },
          "conditions": null,
          "actions": [
            {
              "deviceName": "Living Room Light",
              "characteristic": "Brightness",
              "value": 30,
              "delaySeconds": 0
            }
          ],
          "enabled": true
        }
        """
        
        if let context = deviceContext, !context.isEmpty {
            prompt += """
            
            
            Available devices:
            \(context)
            
            Use exact device names from the list above.
            """
        }
        
        prompt += """
        
        
        Remember: Respond with ONLY the JSON object. No markdown, no explanations, just valid JSON.
        """
        
        return prompt
    }
    
    private func buildUserPrompt(from description: String) -> String {
        return description
    }
    
    // MARK: - API Communication
    
    private nonisolated func sendRequest(system: String, user: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        
        let requestBody: Data
        
        switch provider {
        case .openai:
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ],
                "temperature": 0.3,  // Lower temperature for more consistent JSON
                "max_tokens": 2000
            ]
            requestBody = try JSONSerialization.data(withJSONObject: body)
            
        case .claude:
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 2000,
                "system": system,
                "messages": [
                    ["role": "user", "content": user]
                ],
                "temperature": 0.3
            ]
            requestBody = try JSONSerialization.data(withJSONObject: body)
            
        case .custom:
            // Generic format similar to OpenAI
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ],
                "temperature": 0.3
            ]
            requestBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        request.httpBody = requestBody
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        return try extractContent(from: data, provider: provider)
    }
    
    private nonisolated func extractContent(from data: Data, provider: LLMProvider) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        
        switch provider {
        case .openai, .custom:
            // OpenAI format: choices[0].message.content
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw LLMError.invalidResponse
            }
            return content
            
        case .claude:
            // Claude format: content[0].text
            guard let content = json["content"] as? [[String: Any]],
                  let first = content.first,
                  let text = first["text"] as? String else {
                throw LLMError.invalidResponse
            }
            return text
        }
    }
    
    // MARK: - Response Parsing
    
    private func parseResponse(_ response: String) throws -> AutomationDefinition {
        // Clean up response (remove markdown code blocks if present)
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = cleanedResponse.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedResponse.hasPrefix("```") {
            cleanedResponse = cleanedResponse.replacingOccurrences(of: "```", with: "")
        }
        cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find JSON object boundaries
        if let start = cleanedResponse.firstIndex(of: "{"),
           let end = cleanedResponse.lastIndex(of: "}") {
            cleanedResponse = String(cleanedResponse[start...end])
        }
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw LLMError.parsingFailed("Could not encode response as UTF-8")
        }
        
        do {
            let decoder = JSONDecoder()
            let definition = try decoder.decode(AutomationDefinition.self, from: data)
            
            // Validate required fields
            guard !definition.name.isEmpty else {
                throw LLMError.parsingFailed("Automation name is required")
            }
            guard !definition.actions.isEmpty else {
                throw LLMError.parsingFailed("At least one action is required")
            }
            
            return definition
        } catch {
            throw LLMError.parsingFailed("JSON decode failed: \(error.localizedDescription)\n\nResponse:\n\(cleanedResponse)")
        }
    }
    
    // MARK: - Device Context Helper
    
    /// Fetches device context from HomeKitHelper for better LLM parsing.
    static func fetchDeviceContext() async throws -> String {
        let deviceMap = try await HelperAPIClient.shared.getDeviceMap()
        
        var context = ""
        for home in deviceMap.homes {
            context += "Home: \(home.name)\n"
            for accessory in home.accessories {
                let room = accessory.room ?? "No Room"
                let chars = accessory.characteristics.map { $0.name }.joined(separator: ", ")
                context += "  - \(accessory.name) (\(room)) — \(chars)\n"
            }
        }
        
        return context
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingFailed(String)
    case notConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid LLM endpoint URL"
        case .invalidResponse:
            return "Received invalid response from LLM service"
        case .apiError(let code, let message):
            return "LLM API error (\(code)): \(message)"
        case .parsingFailed(let details):
            return "Failed to parse LLM response: \(details)"
        case .notConfigured:
            return "LLM service is not configured. Please set up your API key in Settings."
        }
    }
}
