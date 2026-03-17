import Foundation

@Observable @MainActor final class UserPreferences {
    private static let key = "pref_useMetric"

    var useMetric: Bool {
        didSet { UserDefaults.standard.set(useMetric, forKey: Self.key) }
    }

    init() {
        if let saved = UserDefaults.standard.object(forKey: Self.key) as? Bool {
            useMetric = saved
        } else {
            useMetric = Locale.current.measurementSystem != .us
        }
    }
}
