import SwiftUI

struct SessionReclassifySheet: View {
    let session: Session
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: ActivityCategory
    @State private var remember: SessionRememberScope

    private let rememberOptions: [SessionRememberScope]

    init(session: Session, onSave: @escaping () -> Void) {
        self.session = session
        self.onSave = onSave
        let initialCategory = session.activityCategory == .uncategorized ? .productive : session.activityCategory
        _category = State(initialValue: initialCategory)
        let options = SessionRememberScope.options(for: session)
        _remember = State(initialValue: .none)
        rememberOptions = options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reclassify")
                    .font(.title3.weight(.semibold))
                Text(SiteCatalog.displayTitle(for: session))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Category", selection: $category) {
                    ForEach(ActivityCategory.allCases.filter { $0 != .uncategorized }, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Remember")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Remember", selection: $remember) {
                    ForEach(rememberOptions, id: \.self) { scope in
                        Text(SessionRememberScope.detailLabel(for: scope, session: session))
                            .tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func save() {
        Task {
            try? await Classifier.shared.applyManualCorrection(
                session: session,
                category: category,
                siteLabel: session.siteLabel,
                remember: remember
            )
            NotificationCenter.default.post(name: .productivityDataDidChange, object: nil)
            onSave()
            dismiss()
        }
    }
}
