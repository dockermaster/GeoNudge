import Foundation
import CoreLocation
import MapKit

struct GoogleMapsLinkParser {

    struct ParsedPlace {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    enum ParserError: LocalizedError {
        case notGoogleMaps
        case noLocationFound
        case geocodingFailed

        var errorDescription: String? {
            switch self {
            case .notGoogleMaps:   return "Not a valid Google Maps link."
            case .noLocationFound: return "Could not extract a location from this link."
            case .geocodingFailed: return "Could not find coordinates for this address."
            }
        }
    }

    // MARK: - Public API

    static func isGoogleMapsURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        let host = url.host ?? ""
        return host.contains("goo.gl") || host.contains("google.com")
    }

    static func parse(url: URL) async throws -> ParsedPlace {
        let resolved = try await resolve(url)

        // Prefer @lat,lon embedded in URL path — no extra network call needed
        if let place = extractCoordinatesFromPath(resolved) { return place }

        // Fall back to ?q= parameter with geocoding
        if let place = try await extractFromQuery(resolved) { return place }

        throw ParserError.noLocationFound
    }

    // MARK: - URL Resolution

    private static func resolve(_ url: URL) async throws -> URL {
        let host = url.host ?? ""
        // Already a direct Google Maps URL — skip redirect resolution
        if host.contains("google.com") && !host.contains("goo.gl") { return url }

        let tracker = RedirectTracker()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config, delegate: tracker, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(from: url)
            return tracker.capturedURL ?? response.url ?? url
        } catch {
            // Thrown when we cancelled the redirect on purpose
            if let captured = tracker.capturedURL { return captured }
            throw ParserError.noLocationFound
        }
    }

    // MARK: - Parsers

    /// Handles share URLs like: .../maps/place/Name/@lat,lon,zoom
    private static func extractCoordinatesFromPath(_ url: URL) -> ParsedPlace? {
        let str = url.absoluteString
        guard let range = str.range(of: #"@(-?\d+\.\d+),(-?\d+\.\d+)"#, options: .regularExpression) else { return nil }
        let coordPart = str[range].dropFirst() // drop "@"
        let parts = coordPart.split(separator: ",")
        guard parts.count >= 2,
              let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }

        let name = url.pathComponents
            .drop(while: { $0 != "place" })
            .dropFirst()
            .first
            .flatMap { $0.removingPercentEncoding }?
            .replacingOccurrences(of: "+", with: " ") ?? "Pinned Location"

        return ParsedPlace(name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    /// Handles redirect targets like: maps.google.com/?q=Business+Name,+Address
    private static func extractFromQuery(_ url: URL) async throws -> ParsedPlace? {
        guard let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "q" })?.value, !q.isEmpty
        else { return nil }

        // ?q=lat,lon — direct coordinates
        let rawParts = q.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        if rawParts.count == 2, let lat = Double(rawParts[0]), let lon = Double(rawParts[1]) {
            return ParsedPlace(name: "Pinned Location",
                               coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        // ?q=Business Name, Full Address — split on first comma for the display name
        // URLComponents decodes %20 but not +, so replace manually
        let decoded = q.replacingOccurrences(of: "+", with: " ")
        let name: String
        if let commaIdx = decoded.firstIndex(of: ",") {
            name = String(decoded[..<commaIdx]).trimmingCharacters(in: .whitespaces)
        } else {
            name = decoded
        }

        // Geocode using the full q string for best accuracy
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            guard let request = MKGeocodingRequest(addressString: q),
                  let item = try await request.mapItems.first
            else { throw ParserError.geocodingFailed }
            coordinate = item.location.coordinate
        } else {
            let geocoder = CLGeocoder()
            guard let placemark = try await geocoder.geocodeAddressString(q).first,
                  let location = placemark.location
            else { throw ParserError.geocodingFailed }
            coordinate = location.coordinate
        }

        return ParsedPlace(name: name, coordinate: coordinate)
    }

    // MARK: - Redirect Tracker

    /// Intercepts the first redirect to a maps.google.com URL and stops there.
    private final class RedirectTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private(set) var capturedURL: URL?

        nonisolated func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url else { completionHandler(request); return }
            let str = url.absoluteString
            if str.contains("maps.google.com") || str.contains("google.com/maps") {
                capturedURL = url
                completionHandler(nil) // Cancel redirect — throws URLError.cancelled upstream
            } else {
                completionHandler(request)
            }
        }
    }
}
