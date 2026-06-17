import Foundation

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var aiClassificationEnabled: Bool {
        get { defaults.object(forKey: "aiClassificationEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "aiClassificationEnabled") }
    }

    var openRouterAPIKey: String {
        get { defaults.string(forKey: "openRouterAPIKey") ?? "" }
        set { defaults.set(newValue, forKey: "openRouterAPIKey") }
    }

    var openRouterOnly: Bool {
        get { defaults.bool(forKey: "openRouterOnly") }
        set { defaults.set(newValue, forKey: "openRouterOnly") }
    }

    var aggressiveRedaction: Bool {
        get { defaults.bool(forKey: "aggressiveRedaction") }
        set { defaults.set(newValue, forKey: "aggressiveRedaction") }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var onboardingResumeStep: Int? {
        get {
            guard defaults.object(forKey: "onboardingResumeStep") != nil else { return nil }
            return defaults.integer(forKey: "onboardingResumeStep")
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "onboardingResumeStep")
            } else {
                defaults.removeObject(forKey: "onboardingResumeStep")
            }
        }
    }

    var loginItemEnabled: Bool {
        get {
            if defaults.object(forKey: "loginItemEnabled") == nil { return true }
            return defaults.bool(forKey: "loginItemEnabled")
        }
        set { defaults.set(newValue, forKey: "loginItemEnabled") }
    }

    var nudgesEnabled: Bool {
        get { defaults.bool(forKey: "nudgesEnabled") }
        set { defaults.set(newValue, forKey: "nudgesEnabled") }
    }

    var nudgeThresholdMinutes: Int {
        get {
            let v = defaults.integer(forKey: "nudgeThresholdMinutes")
            return v > 0 ? v : 20
        }
        set { defaults.set(newValue, forKey: "nudgeThresholdMinutes") }
    }

    var nudgeCooldownMinutes: Int {
        get {
            let v = defaults.integer(forKey: "nudgeCooldownMinutes")
            return v > 0 ? v : 30
        }
        set { defaults.set(newValue, forKey: "nudgeCooldownMinutes") }
    }

    var nudgeRollingWindowMinutes: Int {
        get {
            let v = defaults.integer(forKey: "nudgeRollingWindowMinutes")
            return v > 0 ? v : 60
        }
        set { defaults.set(newValue, forKey: "nudgeRollingWindowMinutes") }
    }

    var quietHoursStart: Int {
        get {
            let v = defaults.integer(forKey: "quietHoursStart")
            return defaults.object(forKey: "quietHoursStart") == nil ? 22 : v
        }
        set { defaults.set(newValue, forKey: "quietHoursStart") }
    }

    var quietHoursEnd: Int {
        get {
            let v = defaults.integer(forKey: "quietHoursEnd")
            return defaults.object(forKey: "quietHoursEnd") == nil ? 8 : v
        }
        set { defaults.set(newValue, forKey: "quietHoursEnd") }
    }

    var workHoursStart: Int {
        get {
            let v = defaults.integer(forKey: "workHoursStart")
            return v > 0 ? v : 9
        }
        set { defaults.set(newValue, forKey: "workHoursStart") }
    }

    var workHoursEnd: Int {
        get {
            let v = defaults.integer(forKey: "workHoursEnd")
            return v > 0 ? v : 18
        }
        set { defaults.set(newValue, forKey: "workHoursEnd") }
    }

    var workContext: String {
        get { defaults.string(forKey: "workContext") ?? "Software engineer" }
        set { defaults.set(newValue, forKey: "workContext") }
    }

    var blocklistedBundleIds: [String] {
        get {
            defaults.stringArray(forKey: "blocklistedBundleIds") ?? Self.defaultBlocklist
        }
        set { defaults.set(newValue, forKey: "blocklistedBundleIds") }
    }

    static let defaultBlocklist = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
    ]
}
