import Foundation

struct GeoCollection: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var isDefault: Bool = false

    private static let defaultsKey = "geo_collections_v1"

    static func loadAll() -> [GeoCollection] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let collections = try? JSONDecoder().decode([GeoCollection].self, from: data)
        else { return [] }
        return collections
    }

    static func saveAll(_ collections: [GeoCollection]) {
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
