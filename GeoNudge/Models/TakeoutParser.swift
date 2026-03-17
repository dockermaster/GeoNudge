import Foundation

enum TakeoutParser {
    private struct FeatureCollection: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let geometry: Geometry?
        let properties: Properties
    }

    private struct Geometry: Decodable {
        let coordinates: [Double]
        let type: String
    }

    private struct Properties: Decodable {
        let title: String
        let location: Location?

        enum CodingKeys: String, CodingKey {
            case title = "Title"
            case location = "Location"
        }
    }

    private struct Location: Decodable {
        let address: String?
        let geoCoordinates: GeoCoordinates?

        enum CodingKeys: String, CodingKey {
            case address = "Address"
            case geoCoordinates = "Geo Coordinates"
        }
    }

    private struct GeoCoordinates: Decodable {
        let latitude: String
        let longitude: String

        enum CodingKeys: String, CodingKey {
            case latitude = "Latitude"
            case longitude = "Longitude"
        }
    }

    static func parse(data: Data, collectionName: String) throws -> (GeoCollection, [GeoAlert]) {
        let collection = GeoCollection(name: collectionName)
        let featureCollection = try JSONDecoder().decode(FeatureCollection.self, from: data)

        let alerts: [GeoAlert] = featureCollection.features.compactMap { feature in
            let title = feature.properties.title

            // GeoJSON coordinates are [longitude, latitude]
            if let coords = feature.geometry?.coordinates, coords.count >= 2 {
                return GeoAlert(
                    name: title,
                    message: "You're near \(title)",
                    latitude: coords[1],
                    longitude: coords[0],
                    radius: 200,
                    collectionId: collection.id
                )
            }

            // Fallback: Location.Geo Coordinates string values
            if let geoCoords = feature.properties.location?.geoCoordinates,
               let lat = Double(geoCoords.latitude),
               let lon = Double(geoCoords.longitude) {
                return GeoAlert(
                    name: title,
                    message: "You're near \(title)",
                    latitude: lat,
                    longitude: lon,
                    radius: 200,
                    collectionId: collection.id
                )
            }

            return nil
        }

        return (collection, alerts)
    }
}
