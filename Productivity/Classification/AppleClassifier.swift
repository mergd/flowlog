import AppKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct ActivityClassification {
    @Guide(description: "productive, neutral, distracting, or uncategorized")
    var category: String
    @Guide(description: "Short site or app label")
    var siteLabel: String
    var confidence: Double
    var reason: String
}
#endif

final class AppleClassifier: @unchecked Sendable {
    static let shared = AppleClassifier()

    private(set) var isSupported = false
    private(set) var status: AppleIntelligenceStatus = .frameworkUnavailable
    private var lastCheck = Date.distantPast

    private init() {}

    func refreshAvailability() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                isSupported = true
                status = .available
            case .unavailable(.deviceNotEligible):
                isSupported = false
                status = .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                isSupported = false
                status = .notEnabled
            case .unavailable(.modelNotReady):
                isSupported = false
                status = .modelNotReady
            case .unavailable:
                isSupported = false
                status = .notEnabled
            }
        } else {
            isSupported = false
            status = .osVersionUnsupported
        }
        #else
        isSupported = false
        status = .frameworkUnavailable
        #endif
        lastCheck = Date()
    }

    func classify(request: ClassificationRequest) async throws -> ClassificationResult {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw ClassifierError.unavailable }
        guard isSupported else { throw ClassifierError.unavailable }

        let workContext = await MainActor.run { AppSettings.shared.workContext }
        let workHoursStart = await MainActor.run { AppSettings.shared.workHoursStart }
        let workHoursEnd = await MainActor.run { AppSettings.shared.workHoursEnd }

        let session = LanguageModelSession {
            """
            You classify Mac activity for productivity tracking.
            Work context: \(workContext), work hours \(workHoursStart)-\(workHoursEnd).
            Judge what the user is actually doing, not just the app or domain.
            The same website can be productive or distracting depending on content
            (e.g. Khan Academy vs entertainment on YouTube).
            Respond with category: productive, neutral, distracting, or uncategorized.
            """
        }

        let prompt = try await buildPrompt(for: request)
        let response = try await session.respond(to: prompt, generating: ActivityClassification.self)
        return map(response.content)
        #else
        throw ClassifierError.unavailable
        #endif
    }

    private func buildPrompt(for request: ClassificationRequest) async throws -> String {
        var lines = [
            "App: \(request.appName) (\(request.bundleId))",
            "Window title: \(request.windowTitle ?? "unknown")"
        ]

        if let imageData = request.imageData, let image = NSImage(data: imageData) {
            if let ocr = await OCRPreprocessor.extractText(from: image), !ocr.isEmpty {
                let snippet = String(ocr.prefix(1500))
                lines.append("Visible page text (OCR): \(snippet)")
            }
            lines.append("A redacted desktop screenshot was captured for this browser session.")
        }

        lines.append("Classify this activity.")
        return lines.joined(separator: "\n")
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func map(_ c: ActivityClassification) -> ClassificationResult {
        ClassificationResult(
            category: ActivityCategory(rawValue: c.category.lowercased()) ?? .uncategorized,
            siteLabel: c.siteLabel.isEmpty ? nil : c.siteLabel,
            confidence: c.confidence,
            reason: c.reason,
            source: .apple
        )
    }
    #endif
}

enum ClassifierError: Error {
    case unavailable
    case noAPIKey
}
