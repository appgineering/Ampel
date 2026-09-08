import Foundation
import Observation

/// User preferences, persisted in UserDefaults. Defaults match the behaviour
/// the app shipped with, so an existing install sees no change.
@MainActor
@Observable
final class Settings {
    enum UsageStyle: String, CaseIterable, Identifiable {
        case bars, text, hidden
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bars: "Bars and numbers"
            case .text: "Numbers only"
            case .hidden: "Hidden"
            }
        }
    }

    var usageStyle: UsageStyle {
        didSet { defaults.set(usageStyle.rawValue, forKey: Key.usageStyle) }
    }

    /// First launch shows the setup guide. Also reachable from About.
    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Key.onboarded) }
    }

    var iconStyle: IconStyle {
        didSet { defaults.set(iconStyle.rawValue, forKey: Key.iconStyle) }
    }

    /// Multiplies the 18pt icon canvas. Capped at 1.2 because the menu bar
    /// clips anything taller than about 22pt.
    var iconScale: Double {
        didSet { defaults.set(iconScale, forKey: Key.iconScale) }
    }

    var pulseOnAttention: Bool {
        didSet { defaults.set(pulseOnAttention, forKey: Key.pulse) }
    }

    var notifyOnAttention: Bool {
        didSet { defaults.set(notifyOnAttention, forKey: Key.notify) }
    }

    private enum Key {
        static let usageStyle = "usageStyle"
        static let iconStyle = "iconStyle"
        static let iconScale = "iconScale"
        static let onboarded = "hasOnboarded"
        static let pulse = "pulseOnAttention"
        static let notify = "notifyOnAttention"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.pulse: true, Key.notify: true, Key.iconScale: 1.0])
        usageStyle = UsageStyle(rawValue: defaults.string(forKey: Key.usageStyle) ?? "") ?? .bars
        iconStyle = IconStyle(rawValue: defaults.string(forKey: Key.iconStyle) ?? "") ?? .dot
        iconScale = defaults.double(forKey: Key.iconScale)
        hasOnboarded = defaults.bool(forKey: Key.onboarded)
        pulseOnAttention = defaults.bool(forKey: Key.pulse)
        notifyOnAttention = defaults.bool(forKey: Key.notify)
    }
}
