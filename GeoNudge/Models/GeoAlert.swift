import Foundation
import CoreLocation

struct GeoAlert: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var message: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var isActive: Bool = true
    var collectionId: UUID?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var regionIdentifier: String { id.uuidString }

    private static let defaultsKey = "geo_alerts_v1"

    static func loadAll() -> [GeoAlert] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let alerts = try? JSONDecoder().decode([GeoAlert].self, from: data)
        else { return [] }
        return alerts
    }

    static func saveAll(_ alerts: [GeoAlert]) {
        if let data = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
