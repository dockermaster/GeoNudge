import SwiftUI

@main
struct GeoNudgeApp: App {
    @State private var notificationManager: NotificationManager
    @State private var locationManager: LocationManager

    init() {
        let nm = NotificationManager()
        let lm = LocationManager(notifier: nm)
        _notificationManager = State(initialValue: nm)
        _locationManager = State(initialValue: lm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(notificationManager)
                .environment(locationManager)
        }
    }
}
