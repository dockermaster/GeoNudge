import Foundation
import CoreLocation

// MARK: - Payload model

enum SharePayload {
    struct AlertData: Identifiable {
        let id = UUID()
        let name: String
        let message: String
        let latitude: Double
        let longitude: Double
        let radius: Double
    }

    case singleAlert(AlertData)
    case collection(name: String, alerts: [AlertData])
}

// MARK: - Encoding

extension SharePayload {
    /// Encodes a single alert as a geonudge:// deep link URL.
    static func url(for alert: GeoAlert) -> URL? {
        var components = URLComponents()
        components.scheme = "geonudge"
        components.host = "alert"
        components.queryItems = [
            URLQueryItem(name: "name",    value: alert.name),
            URLQueryItem(name: "message", value: alert.message),
            URLQueryItem(name: "lat",     value: String(alert.latitude)),
            URLQueryItem(name: "lon",     value: String(alert.longitude)),
            URLQueryItem(name: "radius",  value: String(alert.radius))
        ]
        return components.url
    }

    /// Writes a collection to a temp .geonudge file and returns its URL for sharing.
    static func file(for collection: GeoCollection, alerts: [GeoAlert]) throws -> URL {
        let payload = FilePayload(
            version: 1,
            name: collection.name,
            alerts: alerts.map {
                FilePayload.AlertEntry(
                    name: $0.name,
                    message: $0.message,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    radius: $0.radius
                )
            }
        )
        let data = try JSONEncoder().encode(payload)
        let safeName = collection.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension("geonudge")
        try data.write(to: url)
        return url
    }
}

// MARK: - Decoding

extension SharePayload {
    static func decode(from url: URL) -> SharePayload? {
        if url.scheme == "geonudge" { return decodeURL(url) }
        if url.isFileURL            { return decodeFile(url) }
        return nil
    }

    private static func decodeURL(_ url: URL) -> SharePayload? {
        print("[GeoNudge] decodeURL: host=\(url.host ?? "nil")")
        guard url.host == "alert",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else {
            print("[GeoNudge] decodeURL: failed host/queryItems check")
            return nil
        }

        func q(_ key: String) -> String? { items.first { $0.name == key }?.value?.replacingOccurrences(of: "+", with: " ") }
        print("[GeoNudge] decodeURL: name=\(q("name") ?? "nil") lat=\(q("lat") ?? "nil") lon=\(q("lon") ?? "nil") radius=\(q("radius") ?? "nil")")

        guard let name   = q("name"),
              let latStr = q("lat"), let lat = Double(latStr),
              let lonStr = q("lon"), let lon = Double(lonStr),
              let rStr   = q("radius"), let radius = Double(rStr)
        else {
            print("[GeoNudge] decodeURL: failed to parse required params")
            return nil
        }

        return .singleAlert(AlertData(
            name: name,
            message: q("message") ?? "You're near \(name)",
            latitude: lat,
            longitude: lon,
            radius: radius
        ))
    }

    private static func decodeFile(_ url: URL) -> SharePayload? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data    = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(FilePayload.self, from: data)
        else { return nil }

        let alerts = payload.alerts.map {
            AlertData(name: $0.name, message: $0.message,
                      latitude: $0.latitude, longitude: $0.longitude, radius: $0.radius)
        }
        return .collection(name: payload.name, alerts: alerts)
    }
}

// MARK: - File format (private)

private struct FilePayload: Codable {
    let version: Int
    let name: String
    let alerts: [AlertEntry]

    struct AlertEntry: Codable {
        let name: String
        let message: String
        let latitude: Double
        let longitude: Double
        let radius: Double
    }
}
