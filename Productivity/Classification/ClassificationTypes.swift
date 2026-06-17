import Foundation

struct ClassificationResult: Sendable {
    let category: ActivityCategory
    let siteLabel: String?
    let confidence: Double
    let reason: String?
    let source: ClassificationSource
}

struct ClassificationRequest: Sendable {
    let bundleId: String
    let appName: String
    let windowTitle: String?
    let imageData: Data?
}
