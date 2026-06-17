import Foundation

final class OpenRouterClassifier: Sendable {
    static let shared = OpenRouterClassifier()
    private static let model = "google/gemini-2.5-flash-lite"

    func classify(request: ClassificationRequest) async throws -> ClassificationResult {
        let apiKey = await MainActor.run { AppSettings.shared.openRouterAPIKey }
        guard !apiKey.isEmpty else { throw ClassifierError.noAPIKey }

        var content: [[String: Any]] = [[
            "type": "text",
            "text": await promptText(for: request),
        ]]

        if let imageData = request.imageData {
            let b64 = imageData.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(b64)"],
            ])
        }

        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "user", "content": content],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "classification",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "category": ["type": "string"],
                            "siteLabel": ["type": "string"],
                            "confidence": ["type": "number"],
                            "reason": ["type": "string"],
                        ],
                        "required": ["category", "siteLabel", "confidence", "reason"],
                        "additionalProperties": false,
                    ],
                ],
            ],
        ]

        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClassifierError.unavailable
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let contentStr = message?["content"] as? String ?? ""
        let parsed = try JSONDecoder().decode(ORClassification.self, from: Data(contentStr.utf8))

        return ClassificationResult(
            category: ActivityCategory(rawValue: parsed.category.lowercased()) ?? .uncategorized,
            siteLabel: parsed.siteLabel.isEmpty ? nil : parsed.siteLabel,
            confidence: parsed.confidence,
            reason: parsed.reason,
            source: .openRouter
        )
    }

    private func promptText(for request: ClassificationRequest) async -> String {
        let workContext = await MainActor.run { AppSettings.shared.workContext }
        return """
        Classify Mac activity for productivity tracking.
        Judge what the user is actually doing, not just the app or domain.
        The same website can be productive or distracting depending on content
        (e.g. Khan Academy vs entertainment on YouTube).
        Categories: productive, neutral, distracting, uncategorized.
        Work context: \(workContext)
        App: \(request.appName) (\(request.bundleId))
        Window: \(request.windowTitle ?? "unknown")
        Return JSON only.
        """
    }

    private struct ORClassification: Decodable {
        let category: String
        let siteLabel: String
        let confidence: Double
        let reason: String
    }
}
