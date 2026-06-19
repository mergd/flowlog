import SwiftUI

struct AppsView: View {
    @State private var groups: [AppUsageGroup] = []
    @State private var filter: ActivityCategory?

    var body: some View {
        Group {
            if groups.isEmpty {
                DashboardEmptyState(
                    symbol: "square.grid.2x2",
                    title: "No apps tracked yet",
                    message: "Time per app shows up here once Flowlog has seen you switch between a few apps."
                )
            } else {
                VStack(spacing: 0) {
                    Picker("Filter", selection: $filter) {
                        Text("All").tag(ActivityCategory?.none)
                        ForEach(availableFilters, id: \.self) { cat in
                            Text(cat.displayName).tag(Optional(cat))
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    if filteredGroups.isEmpty {
                        DashboardEmptyState(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: "No matches",
                            message: "Nothing classified as \(filter?.displayName.lowercased() ?? "this filter") yet."
                        )
                    } else {
                        List {
                            ForEach(filteredGroups) { group in
                                appRow(group)

                                if group.isBrowser {
                                    ForEach(visibleSites(for: group)) { site in
                                        siteRow(site)
                                            .listRowInsets(EdgeInsets(top: 2, leading: DashboardTheme.hInset + 32, bottom: 2, trailing: DashboardTheme.hInset))
                                    }
                                }
                            }
                        }
                        .dashboardPlainList()
                    }
                }
                .safeAreaInset(edge: .top) {
                    DashboardDetailHeader("Apps", subtitle: "Time by app and site today")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardSurface()
        .dashboardAutoReload(reload)
    }

    private func appRow(_ group: AppUsageGroup) -> some View {
        let category = ActivityCategory(rawValue: group.category) ?? .uncategorized

        return HStack(spacing: 10) {
            AppIconView(bundleId: group.bundleId, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.appName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if AppSettings.shared.developerMode {
                    Text(group.bundleId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 8)

            DurationLabel(seconds: group.duration)
                .fixedSize(horizontal: true, vertical: false)

            CategoryIcon(category: category, size: 11)
                .opacity(category == .uncategorized ? 0.5 : 1)
                .frame(width: 14)
                .accessibilityLabel(category.displayName)
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 4, leading: DashboardTheme.hInset, bottom: group.isBrowser ? 2 : 4, trailing: DashboardTheme.hInset))
    }

    private func siteRow(_ site: SiteUsageRow) -> some View {
        let category = ActivityCategory(rawValue: site.category) ?? .uncategorized

        return HStack(spacing: 10) {
            SiteIconView(siteLabel: site.siteLabel, domain: site.domain, size: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(site.siteLabel)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let domain = site.domain, domain != site.siteLabel.lowercased() {
                    Text(domain)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 8)

            DurationLabel(seconds: site.duration)
                .fixedSize(horizontal: true, vertical: false)

            CategoryIcon(category: category, size: 11)
                .opacity(category == .uncategorized ? 0.5 : 1)
                .frame(width: 14)
                .accessibilityLabel(category.displayName)
        }
        .padding(.vertical, 2)
    }

    private func visibleSites(for group: AppUsageGroup) -> [SiteUsageRow] {
        guard let filter else { return group.sites }
        return group.sites.filter { $0.category == filter.rawValue }
    }

    private var availableFilters: [ActivityCategory] {
        var present = Set<String>()
        for group in groups {
            present.insert(group.category)
            for site in group.sites {
                present.insert(site.category)
            }
        }
        return ActivityCategory.allCases.filter { $0 != .uncategorized && present.contains($0.rawValue) }
    }

    private var filteredGroups: [AppUsageGroup] {
        guard let filter else { return groups }
        return groups.compactMap { group in
            if group.isBrowser {
                let sites = group.sites.filter { $0.category == filter.rawValue }
                guard !sites.isEmpty else { return nil }
                let duration = sites.reduce(0) { $0 + $1.duration }
                return AppUsageGroup(
                    id: group.id,
                    appName: group.appName,
                    bundleId: group.bundleId,
                    duration: duration,
                    category: filter.rawValue,
                    sites: sites
                )
            }
            guard group.category == filter.rawValue else { return nil }
            return group
        }
    }

    private func reload() {
        groups = DashboardData.usageBreakdownToday()
    }
}
