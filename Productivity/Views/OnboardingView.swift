import AppKit
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome, accessibility, screenRecording, finish
}

@MainActor
struct OnboardingView: View {
    @Bindable var appState: AppState
    @State private var step = OnboardingStep.welcome
    @State private var accessibilityGranted = WindowTitleReader.hasAccessibilityAccess()
    @State private var screenRecordingGranted = Permissions.isScreenRecordingGranted()
    @State private var waitingForAccessibility = false
    @State private var waitingForScreenRecording = false
    @State private var didPromptScreenRecording = false

    private let inset: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepIndicator
                .padding(.horizontal, inset)
                .padding(.top, 44)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, inset)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            footer
                .padding(.horizontal, inset)
                .padding(.top, 4)
                .padding(.bottom, 2)
        }
        .frame(width: 420, height: 368, alignment: .topLeading)
        .background(.background)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear(perform: bootstrapOnboarding)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatus()
            let resolved = resolvedOnboardingStep()
            if resolved.rawValue > step.rawValue {
                step = resolved
                persistOnboardingStep(resolved)
            }
        }
        .onChange(of: step) { _, newStep in
            handleStepChange(newStep)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.primary : Color.primary.opacity(0.12))
                    .frame(width: item == step ? 18 : 6, height: 6)
                    .animation(.easeOut(duration: 0.2), value: step)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep

        case .accessibility:
            stepHeader("Accessibility", detail: "Reads window titles for app and site labels.")
            permissionBlock(
                granted: accessibilityGranted,
                waiting: waitingForAccessibility,
                action: enableAccessibility
            )

        case .screenRecording:
            stepHeader(
                "Screen Recording",
                detail: "Optional redacted captures add context about what you're working on: apps, sites, documents, and more. Everything stays local on your Mac, deletes after 24 hours, and you can turn it off anytime."
            )
            permissionBlock(
                granted: screenRecordingGranted,
                waiting: waitingForScreenRecording,
                action: enableScreenRecording
            )

        case .finish:
            Text("Ready")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("\(AppInfo.name) lives in your menu bar and starts automatically at login. Open it anytime for Activity, Apps, and Rules.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            appIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Menu bar companion")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Tracks where your time goes and how focused you are, quietly in the background.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                welcomeFeature("clock.arrow.circlepath", "Logs apps, window titles, and sessions as you work")
                welcomeFeature("chart.pie.fill", "Scores your day as productive, neutral, or distracting")
                welcomeFeature("menubar.arrow.down.rectangle", "Lives in the menu bar. Open anytime for Activity, Apps, and Rules")
            }
        }
    }

    private var appIcon: some View {
        Group {
            if let image = NSApplication.shared.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
    }

    private func welcomeFeature(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionBlock(
        granted: Bool,
        waiting: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if waiting && !granted {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for permission…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Circle()
                        .fill(granted ? CategoryColors.color(for: .productive) : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(granted ? "Enabled" : "Not enabled")
                        .font(.subheadline)
                        .foregroundStyle(granted ? .primary : .secondary)
                }
            }

            if !granted {
                Button("Open System Settings", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            if step != .welcome {
                Button("Back", action: goBack)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()

            if step == .finish {
                Button("Start", action: { appState.completeOnboarding() })
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(step == .welcome ? "Continue" : "Next", action: goForward)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canContinue: Bool {
        switch step {
        case .welcome, .finish: true
        case .accessibility: accessibilityGranted
        case .screenRecording: screenRecordingGranted
        }
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
        persistOnboardingStep(previous)
    }

    private func goForward() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
        persistOnboardingStep(next)
    }

    private func handleStepChange(_ newStep: OnboardingStep) {
        if newStep != .accessibility {
            waitingForAccessibility = false
        }
        if newStep != .screenRecording {
            waitingForScreenRecording = false
        }
        refreshPermissionStatus()
    }

    private func bootstrapOnboarding() {
        refreshPermissionStatus()
        let resolved = resolvedOnboardingStep()
        step = resolved
        persistOnboardingStep(resolved)
    }

    private func resolvedOnboardingStep() -> OnboardingStep {
        let saved = AppSettings.shared.onboardingResumeStep.flatMap(OnboardingStep.init(rawValue:))

        guard let saved else { return .welcome }

        switch saved {
        case .welcome:
            return .welcome
        case .accessibility:
            if accessibilityGranted {
                return screenRecordingGranted ? .finish : .screenRecording
            }
            return .accessibility
        case .screenRecording, .finish:
            if !accessibilityGranted { return .accessibility }
            if screenRecordingGranted { return .finish }
            return .screenRecording
        }
    }

    private func persistOnboardingStep(_ step: OnboardingStep) {
        AppSettings.shared.onboardingResumeStep = step.rawValue
    }

    private func refreshPermissionStatus() {
        accessibilityGranted = WindowTitleReader.hasAccessibilityAccess()
        screenRecordingGranted = Permissions.isScreenRecordingGranted()

        if accessibilityGranted {
            waitingForAccessibility = false
        }
        if screenRecordingGranted {
            waitingForScreenRecording = false
        }
    }

    private func enableAccessibility() {
        refreshPermissionStatus()
        guard !accessibilityGranted else { return }

        waitingForAccessibility = true
        persistOnboardingStep(.accessibility)
        WindowTitleReader.requestAccessibilityTrust()
        SystemSettings.open(.accessibility)
    }

    private func enableScreenRecording() {
        refreshPermissionStatus()
        guard !screenRecordingGranted else { return }

        waitingForScreenRecording = true
        persistOnboardingStep(.screenRecording)
        if !didPromptScreenRecording {
            didPromptScreenRecording = true
            _ = Permissions.requestScreenRecordingAccess()
        }
        SystemSettings.open(.screenCapture)
    }
}
