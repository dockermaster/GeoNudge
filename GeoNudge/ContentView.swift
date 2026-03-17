import SwiftUI
import CoreLocation
import UIKit
import UniformTypeIdentifiers

struct AlertRowView: View {
    let alert: GeoAlert
    let collectionName: String
    let distance: String?
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.name)
                    .font(.headline)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let distance {
                        Text(distance)
                        Text("·")
                    }
                    Text("\(Int(alert.radius))m radius")
                    Text("·")
                    Text(collectionName)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { alert.isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .opacity(alert.isActive ? 1.0 : 0.5)
    }
}

struct PermissionBannerView: View {
    let text: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.caption)
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.bold())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(color)
        .foregroundStyle(.white)
    }
}

struct ContentView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(GoogleAuthManager.self) private var googleAuthManager
    @Environment(UserPreferences.self) private var userPreferences

    @State private var showingAddAlert = false
    @State private var editingAlert: GeoAlert?
    @State private var filterCollectionId: UUID?
    @State private var showingSettings = false
    @State private var showingFileImporter = false
    @State private var showingImportConfirm = false
    @State private var importConfirmMessage = ""

    private var filteredAlerts: [GeoAlert] {
        guard let id = filterCollectionId else { return locationManager.alerts }
        return locationManager.alerts.filter { alert in
            (alert.collectionId ?? locationManager.defaultCollection.id) == id
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if locationManager.alerts.isEmpty {
                    ContentUnavailableView(
                        "No Alerts",
                        systemImage: "location.slash",
                        description: Text("Tap + to add your first location alert.")
                    )
                } else {
                    List {
                        if locationManager.activeRegionCount >= 18 {
                            Label(
                                "Approaching 20-region iOS limit (\(locationManager.activeRegionCount)/20)",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }

                        ForEach(filteredAlerts) { alert in
                            AlertRowView(
                                alert: alert,
                                collectionName: locationManager.collectionName(for: alert),
                                distance: locationManager.distance(to: alert, useMetric: userPreferences.useMetric)
                            ) {
                                locationManager.toggleActive(alert)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Edit") { editingAlert = alert }
                                    .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    locationManager.delete(alert)
                                }
                            }
                        }
                    }
                    .safeAreaInset(edge: .top) {
                        collectionFilter
                    }
                }
            }
            .navigationTitle("GeoNudge")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddAlert = true
                        } label: {
                            Label("Add Alert", systemImage: "mappin.and.ellipse")
                        }
                        .disabled(!locationManager.canAddMore)

                        Button {
                            handleImportTap()
                        } label: {
                            Label("Import from Google Maps", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAlert) {
                AddAlertView()
            }
            .sheet(item: $editingAlert) { alert in
                AddAlertView(editing: alert)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importTakeoutFile(at: url)
                case .failure:
                    break
                }
            }
            .alert("Import Complete", isPresented: $showingImportConfirm) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importConfirmMessage)
            }
            .safeAreaInset(edge: .top) {
                permissionBanners
            }
            .onAppear {
                locationManager.requestAlwaysAuthorization()
                notificationManager.requestAuthorization()
            }
        }
    }

    private func handleImportTap() {
        if googleAuthManager.isSignedIn {
            showingFileImporter = true
        } else {
            Task {
                guard let vc = rootViewController() else { return }
                try? await googleAuthManager.signIn(presenting: vc)
                if googleAuthManager.isSignedIn {
                    showingFileImporter = true
                }
            }
        }
    }

    private func importTakeoutFile(at url: URL) {
        let collectionName = url.deletingPathExtension().lastPathComponent
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url),
              let (collection, alerts) = try? TakeoutParser.parse(data: data, collectionName: collectionName)
        else {
            importConfirmMessage = "Failed to parse the selected file."
            showingImportConfirm = true
            return
        }

        guard !alerts.isEmpty else {
            importConfirmMessage = "No importable places found in the selected file."
            showingImportConfirm = true
            return
        }

        locationManager.importCollection(collection, alerts: alerts)
        filterCollectionId = collection.id
        importConfirmMessage = "Imported \(alerts.count) place\(alerts.count == 1 ? "" : "s") into \"\(collection.name)\"."
        showingImportConfirm = true
    }

    private func rootViewController() -> UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            .flatMap({ $0 as? UIWindowScene })?
            .keyWindow?
            .rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    @ViewBuilder
    private var collectionFilter: some View {
        if locationManager.collections.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "All", id: nil)
                    ForEach(locationManager.collections) { collection in
                        filterChip(label: collection.name, id: collection.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private func filterChip(label: String, id: UUID?) -> some View {
        let selected = filterCollectionId == id
        return Button {
            filterCollectionId = id
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.secondarySystemFill))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var permissionBanners: some View {
        let locStatus = locationManager.authorizationStatus
        let notifStatus = notificationManager.authorizationStatus

        VStack(spacing: 0) {
            if locStatus == .denied || locStatus == .restricted {
                PermissionBannerView(
                    text: "Location access denied. Alerts won't fire.",
                    color: .red
                )
            } else if locStatus == .authorizedWhenInUse {
                PermissionBannerView(
                    text: "Location set to 'While Using'. Enable 'Always' for background alerts.",
                    color: .orange
                )
            }

            if notifStatus == .denied {
                PermissionBannerView(
                    text: "Notifications disabled. You won't receive alerts.",
                    color: .red
                )
            }
        }
    }
}

#Preview {
    let nm = NotificationManager()
    ContentView()
        .environment(nm)
        .environment(LocationManager(notifier: nm))
        .environment(GoogleAuthManager())
        .environment(UserPreferences())
}
