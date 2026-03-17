import SwiftUI
import CoreLocation
import UIKit
import UniformTypeIdentifiers

// MARK: - Share sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

private struct ShareContent: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct IdentifiablePayload: Identifiable {
    let id = UUID()
    let payload: SharePayload
    init(_ payload: SharePayload) { self.payload = payload }
}

struct AlertRowView: View {
    let alert: GeoAlert
    let collectionName: String
    let distance: String?
    let useMetric: Bool
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
                    Text("\(LocationManager.formatRadius(alert.radius, useMetric: useMetric)) radius")
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
    @State private var shareContent: ShareContent?
    @State private var deepLinkedAlertData: SharePayload.AlertData?
    @State private var incomingCollection: IdentifiablePayload?

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
                                distance: locationManager.distance(to: alert, useMetric: userPreferences.useMetric),
                                useMetric: userPreferences.useMetric
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
                            .contextMenu {
                                Button { editingAlert = alert } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button { shareAlert(alert) } label: {
                                    Label("Share Location", systemImage: "square.and.arrow.up")
                                }
                                Divider()
                                Button(role: .destructive) { locationManager.delete(alert) } label: {
                                    Label("Delete", systemImage: "trash")
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
            .sheet(item: $shareContent) { content in
                ShareSheet(items: content.items)
                    .presentationDetents([.medium])
            }
            .sheet(item: $deepLinkedAlertData) { data in
                AddAlertView(prefilled: data)
            }
            .sheet(item: $incomingCollection) { identifiable in
                ImportPreviewView(payload: identifiable.payload) { payload in
                    applyImport(payload)
                }
            }
            .safeAreaInset(edge: .top) {
                permissionBanners
            }
            .onAppear {
                locationManager.requestAlwaysAuthorization()
                notificationManager.requestAuthorization()
            }
            .onOpenURL { url in
                print("[GeoNudge] ContentView received URL: \(url)")
                print("[GeoNudge] scheme=\(url.scheme ?? "nil"), isFileURL=\(url.isFileURL)")
                guard url.scheme == "geonudge" || url.isFileURL else {
                    print("[GeoNudge] URL ignored - wrong scheme")
                    return
                }
                Task { @MainActor in
                    guard let payload = SharePayload.decode(from: url) else {
                        print("[GeoNudge] SharePayload.decode returned nil")
                        return
                    }
                    print("[GeoNudge] Decoded payload successfully")
                    switch payload {
                    case .singleAlert(let data):
                        print("[GeoNudge] Setting deepLinkedAlertData: \(data.name)")
                        deepLinkedAlertData = data
                        print("[GeoNudge] deepLinkedAlertData is now: \(deepLinkedAlertData?.name ?? "nil")")
                    case .collection(let name, let alerts):
                        print("[GeoNudge] Setting incomingCollection: \(name) (\(alerts.count) alerts)")
                        incomingCollection = IdentifiablePayload(payload)
                    }
                }
            }
        }
    }

    // MARK: - Sharing

    private func shareAlert(_ alert: GeoAlert) {
        guard let url = SharePayload.url(for: alert) else { return }
        shareContent = ShareContent(items: [url])
    }

    private func shareCollection(id: UUID) {
        guard let collection = locationManager.collections.first(where: { $0.id == id }) else { return }
        let alerts = locationManager.alerts.filter {
            ($0.collectionId ?? locationManager.defaultCollection.id) == id
        }
        Task {
            if let fileURL = try? SharePayload.file(for: collection, alerts: alerts) {
                shareContent = ShareContent(items: [fileURL])
            }
        }
    }

    private func applyImport(_ payload: SharePayload) {
        guard case .collection(let name, let alerts) = payload else { return }
        let collection = GeoCollection(name: name)
        let geoAlerts = alerts.map {
            GeoAlert(name: $0.name, message: $0.message,
                     latitude: $0.latitude, longitude: $0.longitude,
                     radius: $0.radius, collectionId: collection.id)
        }
        locationManager.importCollection(collection, alerts: geoAlerts)
        filterCollectionId = collection.id
    }

    // MARK: - Google Takeout import

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
        .contextMenu {
            if let id {
                Button { shareCollection(id: id) } label: {
                    Label("Share Collection", systemImage: "square.and.arrow.up")
                }
            }
        }
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
