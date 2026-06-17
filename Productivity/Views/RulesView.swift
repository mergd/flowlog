import SwiftUI

struct RulesView: View {
    @State private var rules: [Rule] = []
    @State private var newPattern = ""
    @State private var newType = Rule.PatternType.domain
    @State private var newCategory = ActivityCategory.productive
    @State private var isAdding = false
    @FocusState private var patternFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if rules.isEmpty, !isAdding {
                DashboardEmptyState(
                    symbol: "list.bullet.rectangle",
                    title: "No rules yet",
                    message: "Rules teach Flowlog how to classify apps and sites. Add one when you correct a session, or create one here."
                )
                .overlay(alignment: .bottomTrailing) {
                    addButton
                        .padding(24)
                }
            } else {
                List {
                    if isAdding {
                        addRuleSection
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                    }

                    ForEach(rules) { rule in
                        ruleRow(rule)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete(perform: deleteRules)
                }
                .dashboardPlainList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardSurface()
        .safeAreaInset(edge: .top) {
            DashboardDetailHeader(
                "Rules",
                subtitle: rules.isEmpty ? "Classification overrides" : "\(rules.count) active"
            )
        }
        .safeAreaInset(edge: .bottom) {
            if !rules.isEmpty || isAdding {
                HStack {
                    Spacer()
                    if isAdding {
                        Button("Cancel") {
                            isAdding = false
                            newPattern = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    } else {
                        addButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .onAppear(perform: reload)
    }

    private var addButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isAdding = true
                patternFocused = true
            }
        } label: {
            Label("Add Rule", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .opacity(isAdding ? 0.5 : 1)
        .disabled(isAdding)
    }

    private var addRuleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Match", selection: $newType) {
                ForEach(Rule.PatternType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextField(newType.placeholder, text: $newPattern)
                .textFieldStyle(.roundedBorder)
                .focused($patternFocused)

            HStack {
                Text("Classify as")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $newCategory) {
                    ForEach(ActivityCategory.allCases.filter { $0 != .uncategorized }, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .labelsHidden()

                Spacer()

                Button("Save") { saveRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 10) {
            ruleIcon(rule)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let subtitle = rule.displaySubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let type = rule.patternTypeEnum {
                Text(type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }

            CategoryPill(category: rule.activityCategory)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func ruleIcon(_ rule: Rule) -> some View {
        switch rule.patternTypeEnum {
        case .bundleId:
            AppIconView(bundleId: rule.pattern, size: 28)
        case .domain, .siteLabel:
            SiteIconView(
                siteLabel: rule.displayTitle,
                domain: rule.patternTypeEnum == .domain ? rule.pattern : nil,
                size: 28
            )
        default:
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: rule.patternTypeEnum?.icon ?? "questionmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reload() {
        rules = (try? DatabaseManager.shared.allRules()) ?? []
    }

    private func saveRule() {
        let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        try? RulesEngine.shared.addRule(
            patternType: newType,
            pattern: newType == .domain ? pattern.lowercased() : pattern,
            category: newCategory,
            siteLabel: newType == .siteLabel ? pattern : nil
        )
        newPattern = ""
        isAdding = false
        reload()
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            if let id = rules[index].id {
                try? RulesEngine.shared.deleteRule(id: id)
            }
        }
        reload()
    }
}
