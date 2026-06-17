import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var appleStatus = AppleClassifier.shared.status

    var body: some View {
        Form {
            Section("AI") {
                appleIntelligenceStatusCard

                Toggle("Use AI classification", isOn: Bindable(settings).aiClassificationEnabled)

                if !appleStatus.isAvailable, settings.aiClassificationEnabled {
                    Text(fallbackMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("OpenRouter API key", text: Bindable(settings).openRouterAPIKey)
                Toggle("OpenRouter only (testing)", isOn: Bindable(settings).openRouterOnly)
                Toggle("Aggressive screenshot redaction", isOn: Bindable(settings).aggressiveRedaction)
            }

            Section("Nudges") {
                Toggle("Notify when off track", isOn: Bindable(settings).nudgesEnabled)
                    .onChange(of: settings.nudgesEnabled) { _, enabled in
                        if enabled { NudgeEngine.shared.start() }
                    }
                Stepper("Threshold: \(settings.nudgeThresholdMinutes) min/hr", value: Bindable(settings).nudgeThresholdMinutes, in: 5...60, step: 5)
                Stepper("Cooldown: \(settings.nudgeCooldownMinutes) min", value: Bindable(settings).nudgeCooldownMinutes, in: 10...120, step: 5)
                Stepper("Quiet start: \(settings.quietHoursStart):00", value: Bindable(settings).quietHoursStart, in: 0...23)
                Stepper("Quiet end: \(settings.quietHoursEnd):00", value: Bindable(settings).quietHoursEnd, in: 0...23)
            }

            Section("Work context") {
                TextField("Role / context", text: Bindable(settings).workContext)
                Stepper("Work hours start: \(settings.workHoursStart):00", value: Bindable(settings).workHoursStart, in: 0...23)
                Stepper("Work hours end: \(settings.workHoursEnd):00", value: Bindable(settings).workHoursEnd, in: 0...23)
            }

            Section("Privacy") {
                Button("Delete all captures", role: .destructive) {
                    ScreenshotStore.shared.deleteAll()
                }
            }

            Section("Startup") {
                Toggle("Open at login", isOn: Bindable(settings).loginItemEnabled)
                    .onChange(of: settings.loginItemEnabled) { _, enabled in
                        LoginItemManager.setEnabled(enabled)
                    }
            }
            .onAppear {
                settings.loginItemEnabled = LoginItemManager.isRegistered
            }

            Section("Permissions") {
                permissionRow("Accessibility", granted: WindowTitleReader.hasAccessibilityAccess())
                permissionRow("Screen Recording", granted: Permissions.isScreenRecordingGranted())
                Button("Open Accessibility Settings") { openAccessibilitySettings() }
                Button("Open Screen Recording Settings") { openScreenRecordingSettings() }
            }

            Section("About") {
                Button("Show Setup Again…") {
                    AppSettings.shared.hasCompletedOnboarding = false
                    AppSettings.shared.onboardingResumeStep = nil
                    AppState.shared.syncOnboardingState()
                    AppState.shared.presentOnboarding()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .dashboardSurface()
        .frame(minWidth: 420)
        .onAppear(perform: refreshAppleStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAppleStatus()
        }
    }

    private var appleIntelligenceStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: appleStatus.systemImage)
                    .font(.title3)
                    .foregroundStyle(appleStatus.isAvailable ? .primary : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Apple Intelligence")
                            .font(.subheadline.weight(.semibold))
                        Text(appleStatus.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(appleStatus.isAvailable ? Color(red: 0.28, green: 0.78, blue: 0.58) : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((appleStatus.isAvailable ? Color(red: 0.28, green: 0.78, blue: 0.58) : Color.orange).opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(appleStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if appleStatus == .notEnabled || appleStatus == .modelNotReady {
                Button("Open Apple Intelligence Settings") {
                    openAppleIntelligenceSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var fallbackMessage: String {
        if settings.openRouterAPIKey.isEmpty {
            return "Apple Intelligence is not ready. Add an OpenRouter API key or enable Apple Intelligence to classify activity."
        }
        return "Apple Intelligence is not ready. Flowlog will use OpenRouter when configured."
    }

    private func refreshAppleStatus() {
        AppleClassifier.shared.refreshAvailability()
        appleStatus = AppleClassifier.shared.status
    }

    private func permissionRow(_ name: String, granted: Bool) -> some View {
        LabeledContent(name) {
            Text(granted ? "Granted" : "Not granted")
                .foregroundStyle(granted ? .green : .orange)
        }
    }

    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    private func openAppleIntelligenceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.AppleIntelligence-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        }
    }
}
