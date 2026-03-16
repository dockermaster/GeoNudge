import Foundation
import SwiftUI
import CoreLocation
import Observation

// MARK: - Private ObjC delegate bridge

private final class CLLocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    nonisolated(unsafe) weak var owner: LocationManager?

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let owner = self?.owner else { return }
            owner.authorizationStatus = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                owner.syncRegions()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor [weak self] in
            guard let owner = self?.owner,
                  let alert = owner.alerts.first(where: { $0.regionIdentifier == region.identifier }),
                  alert.isActive else { return }
            owner.notifier.schedule(for: alert)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("[LocationManager] Monitoring failed for region \(region?.identifier ?? "unknown"): \(error)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Failed with error: \(error)")
    }
}

// MARK: - Observable location manager

@Observable
@MainActor
final class LocationManager {
    var alerts: [GeoAlert] = GeoAlert.loadAll()
    var collections: [GeoCollection] = GeoCollection.loadAll()
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let coreLocationManager = CLLocationManager()
    private let locationDelegate = CLLocationDelegate()
    let notifier: NotificationManager

    var canAddMore: Bool { alerts.count < 20 }
    var activeRegionCount: Int { alerts.filter(\.isActive).count }

    var defaultCollection: GeoCollection {
        collections.first(where: \.isDefault) ?? collections[0]
    }

    init(notifier: NotificationManager) {
        self.notifier = notifier
        locationDelegate.owner = self
        coreLocationManager.delegate = locationDelegate
        authorizationStatus = coreLocationManager.authorizationStatus
        ensureDefaultCollection()
        syncRegions()
    }

    // MARK: - Collections

    private func ensureDefaultCollection() {
        guard !collections.contains(where: \.isDefault) else { return }
        let def = GeoCollection(name: "General", isDefault: true)
        collections.insert(def, at: 0)
        GeoCollection.saveAll(collections)
    }

    func addCollection(name: String) {
        let collection = GeoCollection(name: name)
        collections.append(collection)
        GeoCollection.saveAll(collections)
    }

    func deleteCollection(_ collection: GeoCollection) {
        guard !collection.isDefault else { return }
        let defaultId = defaultCollection.id
        for i in alerts.indices where alerts[i].collectionId == collection.id {
            alerts[i].collectionId = defaultId
        }
        collections.removeAll { $0.id == collection.id }
        GeoCollection.saveAll(collections)
        GeoAlert.saveAll(alerts)
    }

    func renameCollection(_ collection: GeoCollection, to name: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[idx].name = name
        GeoCollection.saveAll(collections)
    }

    func collectionName(for alert: GeoAlert) -> String {
        guard let id = alert.collectionId,
              let collection = collections.first(where: { $0.id == id })
        else { return defaultCollection.name }
        return collection.name
    }

    // MARK: - Alerts

    func requestAlwaysAuthorization() {
        coreLocationManager.requestAlwaysAuthorization()
    }

    func add(_ alert: GeoAlert) {
        guard canAddMore else {
            print("[LocationManager] Cannot add more alerts: 20-region limit reached")
            return
        }
        alerts.append(alert)
        persist()
        syncRegions()
    }

    func update(_ alert: GeoAlert) {
        guard let idx = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[idx] = alert
        persist()
        syncRegions()
    }

    func delete(_ alert: GeoAlert) {
        alerts.removeAll { $0.id == alert.id }
        persist()
        syncRegions()
    }

    func delete(at offsets: IndexSet) {
        alerts.remove(atOffsets: offsets)
        persist()
        syncRegions()
    }

    func toggleActive(_ alert: GeoAlert) {
        guard let idx = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[idx].isActive.toggle()
        persist()
        syncRegions()
    }

    private func persist() {
        GeoAlert.saveAll(alerts)
    }

    func syncRegions() {
        for region in coreLocationManager.monitoredRegions {
            coreLocationManager.stopMonitoring(for: region)
        }
        for alert in alerts where alert.isActive {
            let region = CLCircularRegion(
                center: alert.coordinate,
                radius: alert.radius,
                identifier: alert.regionIdentifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            coreLocationManager.startMonitoring(for: region)
        }
    }
}
