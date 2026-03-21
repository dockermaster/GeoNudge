import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MapPreviewView: View {
    let coordinate: CLLocationCoordinate2D
    let radius: Double
    let label: String

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius * 4,
            longitudinalMeters: radius * 4
        ))) {
            Marker(label, coordinate: coordinate)
            MapCircle(center: coordinate, radius: radius)
                .foregroundStyle(.blue.opacity(0.2))
                .stroke(.blue, lineWidth: 1.5)
        }
        .disabled(true)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager
    @Environment(UserPreferences.self) private var userPreferences

    private let existingAlert: GeoAlert?

    @State private var name: String
    @State private var message: String
    @State private var radius: Double
    @State private var pickedLocation: PickedLocation?
    @State private var selectedCollectionId: UUID?
    @State private var showingMapPicker = false
    @State private var showingAddCollection = false
    @State private var newCollectionName = ""
    @State private var isResolvingLink = false
    @State private var linkError: String?

    private var isEditing: Bool { existingAlert != nil }

    private var canSave: Bool {
        !name.isEmpty && pickedLocation != nil
    }

    init(prefilled data: SharePayload.AlertData) {
        existingAlert = nil
        _name = State(initialValue: data.name)
        _message = State(initialValue: data.message)
        _radius = State(initialValue: data.radius)
        _selectedCollectionId = State(initialValue: nil)
        _pickedLocation = State(initialValue: PickedLocation(
            coordinate: CLLocationCoordinate2D(latitude: data.latitude, longitude: data.longitude),
            label: data.name
        ))
    }

    init(editing alert: GeoAlert? = nil) {
        existingAlert = alert
        _name = State(initialValue: alert?.name ?? "")
        _message = State(initialValue: alert?.message ?? "")
        _radius = State(initialValue: alert?.radius ?? 200)
        _selectedCollectionId = State(initialValue: alert?.collectionId)
        if let alert {
            _pickedLocation = State(initialValue: PickedLocation(
                coordinate: alert.coordinate,
                label: alert.name
            ))
        } else {
            _pickedLocation = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alert Info") {
                    TextField("Name", text: $name)
                    TextField("Message (optional)", text: $message)
                }

                Section("Location") {
                    if let location = pickedLocation {
                        MapPreviewView(
                            coordinate: location.coordinate,
                            radius: radius,
                            label: location.label
                        )
                        .frame(height: 160)
                        .listRowInsets(EdgeInsets())

                        Text(location.label)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingMapPicker = true
                    } label: {
                        Label(
                            pickedLocation == nil ? "Pick Location" : "Change Location",
                            systemImage: "map"
                        )
                    }

                    Button {
                        pasteGoogleMapsLink()
                    } label: {
                        if isResolvingLink {
                            Label("Resolving link…", systemImage: "link")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Paste Google Maps Link", systemImage: "link")
                        }
                    }
                    .disabled(isResolvingLink)
                }

                Section("Radius: \(LocationManager.formatRadius(radius, useMetric: userPreferences.useMetric))") {
                    Slider(value: $radius, in: 100...1000, step: 50)
                }

                Section("Collection") {
                    Picker("Collection", selection: $selectedCollectionId) {
                        ForEach(locationManager.collections) { collection in
                            Text(collection.name).tag(collection.id as UUID?)
                        }
                    }

                    Button {
                        showingAddCollection = true
                    } label: {
                        Label("New Collection", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Alert" : "New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .fullScreenCover(isPresented: $showingMapPicker) {
                MapPickerView(pickedLocation: $pickedLocation)
            }
            .onChange(of: pickedLocation) { _, newValue in
                if let loc = newValue, name.isEmpty {
                    name = loc.label
                }
            }
            .alert("New Collection", isPresented: $showingAddCollection) {
                TextField("Name", text: $newCollectionName)
                Button("Add") {
                    let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        locationManager.addCollection(name: trimmed)
                        selectedCollectionId = locationManager.collections.last?.id
                    }
                    newCollectionName = ""
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
            .onAppear {
                if selectedCollectionId == nil {
                    selectedCollectionId = locationManager.defaultCollection.id
                }
            }
            .alert("Could Not Import Link", isPresented: Binding(
                get: { linkError != nil },
                set: { if !$0 { linkError = nil } }
            )) {
                Button("OK", role: .cancel) { linkError = nil }
            } message: {
                Text(linkError ?? "")
            }
        }
    }

    private func pasteGoogleMapsLink() {
        guard let raw = UIPasteboard.general.string,
              GoogleMapsLinkParser.isGoogleMapsURL(raw),
              let url = URL(string: raw)
        else {
            linkError = "No Google Maps link found in clipboard."
            return
        }

        isResolvingLink = true
        Task {
            defer { isResolvingLink = false }
            do {
                let place = try await GoogleMapsLinkParser.parse(url: url)
                pickedLocation = PickedLocation(coordinate: place.coordinate, label: place.name)
                if name.isEmpty { name = place.name }
            } catch {
                linkError = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let location = pickedLocation else { return }
        let finalMessage = message.isEmpty ? "You arrived at \(name)." : message
        let collectionId = selectedCollectionId ?? locationManager.defaultCollection.id

        if var alert = existingAlert {
            alert.name = name
            alert.message = finalMessage
            alert.latitude = location.coordinate.latitude
            alert.longitude = location.coordinate.longitude
            alert.radius = radius
            alert.collectionId = collectionId
            locationManager.update(alert)
        } else {
            let alert = GeoAlert(
                name: name,
                message: finalMessage,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radius: radius,
                collectionId: collectionId
            )
            locationManager.add(alert)
        }
        dismiss()
    }
}
