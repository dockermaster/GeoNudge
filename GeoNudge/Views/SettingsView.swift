import SwiftUI
import GoogleSignIn

struct SettingsView: View {
    @Environment(GoogleAuthManager.self) private var googleAuthManager
    @Environment(UserPreferences.self) private var userPreferences

    var body: some View {
        @Bindable var prefs = userPreferences
        NavigationStack {
            List {
                Section("Units") {
                    Picker("Units", selection: $prefs.useMetric) {
                        Text("Imperial").tag(false)
                        Text("Metric").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if googleAuthManager.isSignedIn, let user = googleAuthManager.currentUser {
                    Section("Google Account") {
                        HStack(spacing: 12) {
                            if let photoURL = user.profile?.imageURL(withDimension: 80) {
                                AsyncImage(url: photoURL) { image in
                                    image.resizable()
                                } placeholder: {
                                    Circle().fill(Color.secondary.opacity(0.3))
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.profile?.name ?? "")
                                    .font(.headline)
                                Text(user.profile?.email ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button("Disconnect", role: .destructive) {
                            googleAuthManager.signOut()
                        }
                    }
                }

                Section("Notifications") {
                    Toggle("Sound", isOn: $prefs.notificationSound)
                    Toggle("Vibration", isOn: $prefs.notificationVibration)
                }

                // Future preferences go here

                Section {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                    LabeledContent("Version", value: "\(version) (\(build))")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
