import SwiftUI
import CoreLocation
import UIKit

struct AlertRowView: View {
    let alert: GeoAlert
    let collectionName: String
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

    @State private var showingAddAlert = false
    @State private var editingAlert: GeoAlert?
    @State private var filterCollectionId: UUID?

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
                                collectionName: locationManager.collectionName(for: alert)
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!locationManager.canAddMore)
                }
            }
            .sheet(isPresented: $showingAddAlert) {
                AddAlertView()
            }
            .sheet(item: $editingAlert) { alert in
                AddAlertView(editing: alert)
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
}
