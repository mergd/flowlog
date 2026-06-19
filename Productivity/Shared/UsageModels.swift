import Foundation

struct SiteUsageRow: Identifiable, Sendable {
    let id: String
    let siteLabel: String
    let domain: String?
    let duration: TimeInterval
    let category: String
}

struct AppUsageGroup: Identifiable, Sendable {
    let id: String
    let appName: String
    let bundleId: String
    let duration: TimeInterval
    let category: String
    let sites: [SiteUsageRow]

    var isBrowser: Bool { !sites.isEmpty }
}

/// One app/context's share of time within a block.
struct BlockShare: Identifiable, Sendable {
    let id: String
    let label: String
    let bundleId: String
    let domain: String?
    let category: ActivityCategory
    let duration: TimeInterval
}

/// A contiguous stretch of activity with a coherent intent. Spans multiple apps
/// (Cursor + terminal + Slack → one "work" block); a sustained category change
/// starts a new block, while brief off-category excursions fold in. The label is
/// the dominant app/site, so the timeline reads as a story rather than 30 rows.
struct ActivityBlock: Identifiable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let category: ActivityCategory
    let activeDuration: TimeInterval
    let switchCount: Int
    let shares: [BlockShare]

    var span: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var title: String { shares.first?.label ?? category.displayName }
    /// Apps/sites beyond the dominant one, for a "…with X, Y" summary line.
    var secondaryLabels: [String] { shares.dropFirst().map(\.label) }
}

/// Groups ordered activity slices into intent-coherent blocks. Pure logic over
/// `Session` rows (which are already run-length slices keyed by app+context).
enum BlockBuilder {
    /// A gap larger than this ends the current block (genuine idle/away).
    static let idleGap: TimeInterval = 5 * 60
    /// An off-category excursion shorter than this folds into the surrounding
    /// block instead of splitting it (a quick Slack glance mid-work).
    static let excursionTolerance: TimeInterval = 120

    static func build(from sessions: [Session]) -> [ActivityBlock] {
        let ordered = sessions.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return [] }

        var blocks: [[Session]] = []
        var current: [Session] = []
        var currentCategory: ActivityCategory = .uncategorized
        var excursion: [Session] = []

        func close() {
            if !excursion.isEmpty { current.append(contentsOf: excursion); excursion = [] }
            if !current.isEmpty { blocks.append(current) }
            current = []
        }

        for slice in ordered {
            let category = slice.activityCategory
            if current.isEmpty {
                current = [slice]
                currentCategory = category
                continue
            }

            let lastEnd = endDate(of: current + excursion)
            if slice.start.timeIntervalSince(lastEnd) > idleGap {
                close()
                current = [slice]
                currentCategory = category
                continue
            }

            if category == currentCategory {
                // Back on the block's intent — absorb any brief pending excursion.
                if !excursion.isEmpty { current.append(contentsOf: excursion); excursion = [] }
                current.append(slice)
            } else {
                excursion.append(slice)
                if totalDuration(of: excursion) > excursionTolerance {
                    // Sustained deviation → the prior block ends, the excursion becomes the next.
                    if !current.isEmpty { blocks.append(current) }
                    current = excursion
                    excursion = []
                    currentCategory = dominantCategory(of: current)
                }
            }
        }
        close()

        return blocks.map(makeBlock)
    }

    private static func endDate(of group: [Session]) -> Date {
        group.map { $0.end ?? $0.start.addingTimeInterval(max(0, $0.duration)) }.max() ?? .distantPast
    }

    private static func totalDuration(of group: [Session]) -> TimeInterval {
        group.reduce(0) { $0 + max(0, $1.duration) }
    }

    private static func dominantCategory(of group: [Session]) -> ActivityCategory {
        var totals: [ActivityCategory: TimeInterval] = [:]
        for s in group { totals[s.activityCategory, default: 0] += max(0, s.duration) }
        return totals.max { $0.value < $1.value }?.key ?? .uncategorized
    }

    private static func makeBlock(_ group: [Session]) -> ActivityBlock {
        let start = group.map(\.start).min() ?? Date()
        let end = endDate(of: group)
        let category = dominantCategory(of: group)

        var shareMap: [String: BlockShare] = [:]
        var order: [String] = []
        for slice in group {
            let label = SiteCatalog.displayTitle(for: slice)
            let key = "\(slice.bundleId)|\(label)"
            if let existing = shareMap[key] {
                shareMap[key] = BlockShare(
                    id: key, label: label, bundleId: slice.bundleId, domain: existing.domain,
                    category: existing.category, duration: existing.duration + max(0, slice.duration)
                )
            } else {
                order.append(key)
                let domain = SiteCatalog.parse(windowTitle: slice.windowTitle).domain
                    ?? slice.siteLabel.flatMap { $0.contains(".") ? $0 : nil }
                shareMap[key] = BlockShare(
                    id: key, label: label, bundleId: slice.bundleId, domain: domain,
                    category: slice.activityCategory, duration: max(0, slice.duration)
                )
            }
        }
        let shares = order.compactMap { shareMap[$0] }.sorted { $0.duration > $1.duration }

        return ActivityBlock(
            id: "block-\(Int(start.timeIntervalSince1970))-\(group.first?.id ?? 0)",
            start: start,
            end: end,
            category: category,
            activeDuration: totalDuration(of: group),
            switchCount: group.count,
            shares: shares
        )
    }
}
