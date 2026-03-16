import SwiftUI
import MapKit
import CoreLocation
import Observation

// MARK: - Shared type

struct PickedLocation: Equatable {
    var coordinate: CLLocationCoordinate2D
    var label: String

    static func == (lhs: PickedLocation, rhs: PickedLocation) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.label == rhs.label
    }
}

// MARK: - Private ObjC delegate bridge

private final class MKSearchDelegate: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    nonisolated(unsafe) weak var owner: SearchCompleter?

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak self] in
            self?.owner?.results = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("[SearchCompleter] Failed: \(error)")
    }
}

// MARK: - Observable search completer

@Observable
@MainActor
final class SearchCompleter {
    var query: String = ""
    var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private let searchDelegate = MKSearchDelegate()

    init() {
        searchDelegate.owner = self
        completer.delegate = searchDelegate
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        completer.queryFragment = query
    }
}

// MARK: - View

struct MapPickerView: View {
    @Binding var pickedLocation: PickedLocation?
    @Environment(\.dismiss) private var dismiss

    @State private var searchCompleter = SearchCompleter()
    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var pinnedCoordinate: CLLocationCoordinate2D?
    @State private var pinnedLabel: String = ""
    @State private var isSearching: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let coord = pinnedCoordinate {
                            Marker(pinnedLabel.isEmpty ? "Pin" : pinnedLabel, coordinate: coord)
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onEnded { value in
                                if case .second(true, let drag) = value,
                                   let coord = proxy.convert(drag?.startLocation ?? .zero, from: .local) {
                                    pinAt(coord)
                                }
                            }
                    )
                }

                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search for a place", text: $searchCompleter.query)
                            .autocorrectionDisabled()
                            .onSubmit { isSearching = false }
                        if !searchCompleter.query.isEmpty {
                            Button {
                                searchCompleter.query = ""
                                isSearching = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: searchCompleter.query) { _, newValue in
                        isSearching = !newValue.isEmpty
                        searchCompleter.search(query: newValue)
                    }

                    if isSearching && !searchCompleter.results.isEmpty {
                        List(searchCompleter.results, id: \.self) { result in
                            Button {
                                selectResult(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 250)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Pick Location")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if pinnedCoordinate == nil {
                    Text("Search for an address or long press to drop a pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        if let coord = pinnedCoordinate {
                            pickedLocation = PickedLocation(coordinate: coord, label: pinnedLabel)
                        }
                        dismiss()
                    }
                    .disabled(pinnedCoordinate == nil)
                }
            }
        }
    }

    private func pinAt(_ coord: CLLocationCoordinate2D) {
        pinnedCoordinate = coord
        pinnedLabel = ""
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            ))
        }
        Task { @MainActor in
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let request = MKReverseGeocodingRequest(location: location),
               let items = try? await request.mapItems,
               let name = items.first?.name {
                pinnedLabel = name
            } else {
                pinnedLabel = "Dropped Pin"
            }
        }
    }

    private func selectResult(_ result: MKLocalSearchCompletion) {
        isSearching = false
        searchCompleter.query = result.title

        let request = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: request)
        Task {
            if let response = try? await search.start(),
               let item = response.mapItems.first {
                let coord = item.location.coordinate
                pinnedCoordinate = coord
                pinnedLabel = result.title
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 1000,
                        longitudinalMeters: 1000
                    ))
                }
            }
        }
    }
}
