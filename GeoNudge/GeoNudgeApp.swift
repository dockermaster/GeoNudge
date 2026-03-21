import SwiftUI
import GoogleSignIn

@main
struct GeoNudgeApp: App {
    @State private var notificationManager: NotificationManager
    @State private var locationManager: LocationManager
    @State private var googleAuthManager = GoogleAuthManager()
    @State private var userPreferences: UserPreferences

    init() {
        let up = UserPreferences()
        let nm = NotificationManager(preferences: up)
        let lm = LocationManager(notifier: nm)
        _userPreferences = State(initialValue: up)
        _notificationManager = State(initialValue: nm)
        _locationManager = State(initialValue: lm)

        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(notificationManager)
                .environment(locationManager)
                .environment(googleAuthManager)
                .environment(userPreferences)
                .onOpenURL { url in
                    print("[GeoNudge] App received URL: \(url)")
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    await googleAuthManager.restorePreviousSignIn()
                }
        }
    }
}
