import SwiftUI

struct RulesView: View {
    @State private var rules: [Rule] = []
    @State private var newPattern = ""
    @State private var newType = Rule.PatternType.domain
    @State private var newCategory = ActivityCategory.productive
    @State private var isAdding = false
    @State private var saveError: String?
    @State private var hasInvalidRules = false
    @FocusState private var patternFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            DashboardDetailHeader(
                "Rules",
                subtitle: rules.isEmpty ? "Classification overrides" : "\(rules.count) active"
            )

            Group {
                if rules.isEmpty, !isAdding {
                    DashboardEmptyState(
                        symbol: "list.bullet.rectangle",
                        title: "No rules yet",
                        message: "Rules teach Flowlog how to classify apps and sites. Reclassify a session on the Day tab, or add one here."
                    )
                    .overlay(alignment: .bottomTrailing) {
                        addButton
                            .padding(24)
                    }
                } else {
                    List {
                        if isAdding {
                            addRuleSection
                                .listRowInsets(EdgeInsets(top: 8, leading: DashboardTheme.hInset, bottom: 8, trailing: DashboardTheme.hInset))
                                .listRowSeparator(.hidden)
                        }

                        ForEach(rules) { rule in
                            ruleRow(rule)
                                .listRowInsets(EdgeInsets(top: 4, leading: DashboardTheme.hInset, bottom: 4, trailing: DashboardTheme.hInset))
                        }
                        .onDelete(perform: deleteRules)
                    }
                    .dashboardPlainList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !rules.isEmpty || isAdding {
                HStack {
                    if hasInvalidRules {
                        Button("Clean up invalid") {
                            cleanupInvalid()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isAdding {
                        Button("Cancel") {
                            isAdding = false
                            newPattern = ""
                            saveError = nil
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardSurface()
        .dashboardAutoReload(reload)
    }

    private var addButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isAdding = true
                saveError = nil
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Match type")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Match type", selection: $newType) {
                    ForEach(Rule.PatternType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pattern")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField(newType.placeholder, text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .focused($patternFocused)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Classify as")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $newCategory) {
                    ForEach(ActivityCategory.allCases.filter { $0 != .uncategorized }, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
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

            CategoryIcon(category: rule.activityCategory, size: 11)
                .frame(width: 14)
                .accessibilityLabel(rule.activityCategory.displayName)
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
        let all = DashboardData.allRules()
        rules = all.filter(RuleValidator.isValid)
        hasInvalidRules = all.count != rules.count
    }

    private func cleanupInvalid() {
        _ = try? RulesEngine.shared.deleteInvalidRules()
        reload()
    }

    private func saveRule() {
        let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }

        guard RuleValidator.isValid(pattern: pattern, type: newType) else {
            saveError = "That pattern is not valid."
            return
        }

        do {
            try RulesEngine.shared.addRule(
                patternType: newType,
                pattern: pattern,
                category: newCategory,
                siteLabel: newType == .siteLabel ? pattern : nil
            )
            newPattern = ""
            isAdding = false
            saveError = nil
            reload()
        } catch {
            saveError = error.localizedDescription
        }
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
