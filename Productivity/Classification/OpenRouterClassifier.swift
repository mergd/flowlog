import Foundation

final class OpenRouterClassifier: Sendable {
    static let shared = OpenRouterClassifier()
    private static let model = "google/gemini-2.5-flash-lite"
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")

    func classify(request: ClassificationRequest) async throws -> ClassificationResult {
        let apiKey = await MainActor.run { AppSettings.shared.openRouterAPIKey }
        guard !apiKey.isEmpty else { throw ClassifierError.noAPIKey }
        guard let endpoint = Self.endpoint else { throw ClassifierError.unavailable }

        var content: [ContentBlock] = [.text(await promptText(for: request))]
        if let imageData = request.imageData {
            content.append(.image(base64: imageData.base64EncodedString()))
        }

        let body = RequestBody(model: Self.model, content: content)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClassifierError.unavailable
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let contentStr = decoded.choices.first?.message.content else {
            throw ClassifierError.unavailable
        }
        let parsed = try JSONDecoder().decode(ClassificationPayload.self, from: Data(contentStr.utf8))

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
}

private extension OpenRouterClassifier {
    enum ContentBlock: Encodable {
        case text(String)
        case image(base64: String)

        enum CodingKeys: String, CodingKey {
            case type, text, image_url
        }

        struct ImageURL: Encodable {
            let url: String
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let base64):
                try container.encode("image_url", forKey: .type)
                try container.encode(ImageURL(url: "data:image/jpeg;base64,\(base64)"), forKey: .image_url)
            }
        }
    }

    struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let response_format: ResponseFormat

        init(model: String, content: [ContentBlock]) {
            self.model = model
            messages = [Message(role: "user", content: content)]
            response_format = ResponseFormat()
        }

        struct Message: Encodable {
            let role: String
            let content: [ContentBlock]
        }

        struct ResponseFormat: Encodable {
            let type = "json_schema"
            let json_schema = JSONSchema()
        }

        struct JSONSchema: Encodable {
            let name = "classification"
            let strict = true
            let schema = SchemaDefinition()
        }

        struct SchemaDefinition: Encodable {
            let type = "object"
            let properties = Properties()
            let required = ["category", "siteLabel", "confidence", "reason"]
            let additionalProperties = false

            struct Properties: Encodable {
                let category = Property(type: "string")
                let siteLabel = Property(type: "string")
                let confidence = Property(type: "number")
                let reason = Property(type: "string")
            }

            struct Property: Encodable {
                let type: String
            }
        }
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    struct ClassificationPayload: Decodable {
        let category: String
        let siteLabel: String
        let confidence: Double
        let reason: String
    }
}
