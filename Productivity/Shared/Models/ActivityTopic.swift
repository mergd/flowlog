import Foundation

/// A Screen Time–style *topic* taxonomy: what kind of thing an app or site is,
/// independent of whether it's productive. An app can be `.social` and
/// `.distracting`, or `.developer` and `.productive` — the two axes are
/// orthogonal. Derived from the App Store `LSApplicationCategoryType` taxonomy,
/// plus a curated site mapping.
enum ActivityTopic: String, Codable, CaseIterable, Sendable {
    case developer
    case productivity
    case business
    case education
    case design
    case social
    case communication
    case games
    case entertainment
    case music
    case video
    case photography
    case news
    case finance
    case shopping
    case reference
    case utilities
    case lifestyle
    case health
    case travel
    case food
    case sports
    case ai
    case uncategorized

    var displayName: String {
        switch self {
        case .developer: "Developer"
        case .productivity: "Productivity"
        case .business: "Business"
        case .education: "Education"
        case .design: "Design"
        case .social: "Social"
        case .communication: "Communication"
        case .games: "Games"
        case .entertainment: "Entertainment"
        case .music: "Music"
        case .video: "Video"
        case .photography: "Photography"
        case .news: "News"
        case .finance: "Finance"
        case .shopping: "Shopping"
        case .reference: "Reference"
        case .utilities: "Utilities"
        case .lifestyle: "Lifestyle"
        case .health: "Health & Fitness"
        case .travel: "Travel"
        case .food: "Food & Drink"
        case .sports: "Sports"
        case .ai: "AI"
        case .uncategorized: "Other"
        }
    }

    /// SF Symbol for the topic, used in breakdowns and legends.
    var iconName: String {
        switch self {
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .productivity: "checklist"
        case .business: "briefcase.fill"
        case .education: "graduationcap.fill"
        case .design: "paintbrush.pointed.fill"
        case .social: "bubble.left.and.bubble.right.fill"
        case .communication: "envelope.fill"
        case .games: "gamecontroller.fill"
        case .entertainment: "popcorn.fill"
        case .music: "music.note"
        case .video: "play.rectangle.fill"
        case .photography: "camera.fill"
        case .news: "newspaper.fill"
        case .finance: "dollarsign.circle.fill"
        case .shopping: "cart.fill"
        case .reference: "book.fill"
        case .utilities: "wrench.and.screwdriver.fill"
        case .lifestyle: "sparkles"
        case .health: "heart.fill"
        case .travel: "airplane"
        case .food: "fork.knife"
        case .sports: "sportscourt.fill"
        case .ai: "brain"
        case .uncategorized: "square.grid.2x2"
        }
    }

    /// Resolve the topic for a tracked context. For browsers the topic reflects
    /// the *site* (a browser itself has no topic); for other apps it reflects the
    /// app. Falls back to `.uncategorized` when nothing recognizes the context.
    static func resolve(bundleId: String, domain: String?, siteLabel: String?) -> ActivityTopic {
        if BrowserDetector.isBrowser(bundleId) {
            if let domain, let topic = SiteCatalog.topic(forDomain: domain) { return topic }
            if let topic = SiteCatalog.topic(forLabel: siteLabel) { return topic }
            return .uncategorized
        }
        return AppCatalog.topic(for: bundleId) ?? .uncategorized
    }
}
