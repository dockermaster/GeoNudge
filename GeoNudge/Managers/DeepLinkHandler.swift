import Foundation

@Observable @MainActor final class DeepLinkHandler {
    private(set) var pendingPayload: SharePayload? = nil
    private(set) var payloadID: UUID? = nil

    func set(_ payload: SharePayload) {
        pendingPayload = payload
        payloadID = UUID()
    }

    func clear() {
        pendingPayload = nil
        payloadID = nil
    }
}
