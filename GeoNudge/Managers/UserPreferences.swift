import Foundation

@Observable @MainActor final class UserPreferences {
    private static let metricKey       = "pref_useMetric"
    private static let soundKey        = "pref_notificationSound"
    private static let vibrationKey    = "pref_notificationVibration"

    var useMetric: Bool {
        didSet { UserDefaults.standard.set(useMetric, forKey: Self.metricKey) }
    }

    var notificationSound: Bool {
        didSet { UserDefaults.standard.set(notificationSound, forKey: Self.soundKey) }
    }

    var notificationVibration: Bool {
        didSet { UserDefaults.standard.set(notificationVibration, forKey: Self.vibrationKey) }
    }

    init() {
        if let saved = UserDefaults.standard.object(forKey: Self.metricKey) as? Bool {
            useMetric = saved
        } else {
            useMetric = Locale.current.measurementSystem != .us
        }
        notificationSound     = UserDefaults.standard.object(forKey: Self.soundKey)     as? Bool ?? true
        notificationVibration = UserDefaults.standard.object(forKey: Self.vibrationKey) as? Bool ?? true
    }
}
