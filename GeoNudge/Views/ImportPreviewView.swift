import SwiftUI

struct ImportPreviewView: View {
    let payload: SharePayload
    let onImport: (SharePayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var userPreferences

    var body: some View {
        NavigationStack {
            List {
                Section {
                    switch payload {
                    case .singleAlert(let data):
                        LabeledContent("Name", value: data.name)
                        LabeledContent("Coordinates") {
                            Text(String(format: "%.4f, %.4f", data.latitude, data.longitude))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Radius", value: LocationManager.formatRadius(data.radius, useMetric: userPreferences.useMetric))
                        LabeledContent("Message", value: data.message)

                    case .collection(let name, let alerts):
                        LabeledContent("Collection", value: name)
                        LabeledContent("Locations", value: "\(alerts.count)")
                    }
                } header: {
                    Text(sectionHeader)
                }
            }
            .navigationTitle("Add to GeoNudge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(payload)
                        dismiss()
                    }
                }
            }
        }
    }

    private var sectionHeader: String {
        switch payload {
        case .singleAlert: return "Location"
        case .collection:  return "Collection"
        }
    }
}
