import Foundation
import Observation

@Observable
final class MoofPreferences {
    static let shared = MoofPreferences()

    /// Seconds before info / success cards auto-dismiss. `0` keeps them until dismissed.
    var standardDismissDelay: Int {
        didSet {
            assert((0...3_600).contains(standardDismissDelay), "Standard dismiss delay is out of range.")
            UserDefaults.standard.set(standardDismissDelay, forKey: Key.standardDismissDelay)
        }
    }

    /// Seconds before warning / error cards auto-dismiss. `0` keeps them until dismissed.
    var alertDismissDelay: Int {
        didSet {
            assert((0...3_600).contains(alertDismissDelay), "Alert dismiss delay is out of range.")
            UserDefaults.standard.set(alertDismissDelay, forKey: Key.alertDismissDelay)
        }
    }

    var defaultHeightLevel: Int {
        didSet {
            assert(MoofNotificationLayout.heightRange.contains(defaultHeightLevel), "Height level is out of range.")
            UserDefaults.standard.set(defaultHeightLevel, forKey: Key.defaultHeightLevel)
        }
    }

    /// Theme for cards whose URL has no `theme`.
    var theme: MoofTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Key.theme)
        }
    }

    private enum Key {
        static let standardDismissDelay = "StandardDismissDelay"
        static let alertDismissDelay = "AlertDismissDelay"
        static let defaultHeightLevel = "DefaultHeightLevel"
        static let theme = "Theme"
    }

    private init() {
        let defaults = UserDefaults.standard
        standardDismissDelay = defaults.object(forKey: Key.standardDismissDelay) as? Int ?? 5
        alertDismissDelay = defaults.object(forKey: Key.alertDismissDelay) as? Int ?? 30
        defaultHeightLevel = defaults.object(forKey: Key.defaultHeightLevel) as? Int ?? 1
        theme = defaults.string(forKey: Key.theme).flatMap(MoofTheme.init(rawValue:)) ?? .standard
    }

    func dismissDelay(for notification: MoofNotification) -> TimeInterval? {
        guard !notification.keepsVisibleUntilDismissed else { return nil }
        let delay = notification.duration ?? TimeInterval(notification.style.isAlert ? alertDismissDelay : standardDismissDelay)
        return delay == 0 ? nil : delay
    }
}
