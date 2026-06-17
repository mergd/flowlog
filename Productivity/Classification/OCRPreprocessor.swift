import Foundation
import Vision
import AppKit

enum OCRPreprocessor {
    static func extractText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let strings = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: strings.joined(separator: " "))
            }
            request.recognitionLevel = .fast
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    static func extractDomain(from text: String?) -> String? {
        guard let text else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        for match in matches {
            if let url = match.url?.host?.replacingOccurrences(of: "www.", with: "") {
                return url.lowercased()
            }
        }
        return nil
    }
}
