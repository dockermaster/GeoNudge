import UIKit
import UniformTypeIdentifiers
import UserNotifications

// Must match the App Group ID configured in both targets' Signing & Capabilities.
private let appGroupID    = "group.geonudge"
private let pendingURLKey = "pendingGoogleMapsURL"

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        print("[GeoNudgeExt] ▶️ viewDidLoad — extension launched")
        view.backgroundColor = .clear
        extractAndStore()
    }

    // MARK: - Extract shared URL and write to App Group

    private func extractAndStore() {
        print("[GeoNudgeExt] extractAndStore — checking inputItems")
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            print("[GeoNudgeExt] ❌ No NSExtensionItem in inputItems")
            done(); return
        }

        let attachments = item.attachments ?? []
        print("[GeoNudgeExt] Found \(attachments.count) attachment(s)")
        attachments.forEach { p in
            print("[GeoNudgeExt]   attachment types: \(p.registeredTypeIdentifiers)")
        }

        if let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            print("[GeoNudgeExt] Loading as public.url")
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] value, error in
                print("[GeoNudgeExt] loadItem(url) value=\(String(describing: value)) error=\(String(describing: error))")
                DispatchQueue.main.async { self?.store(value as? URL) }
            }
        } else if let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            print("[GeoNudgeExt] Loading as plain text")
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] value, error in
                print("[GeoNudgeExt] loadItem(text) value=\(String(describing: value)) error=\(String(describing: error))")
                let url = (value as? String).flatMap { text in
                    text.components(separatedBy: .whitespacesAndNewlines)
                        .first(where: { $0.hasPrefix("http") })
                        .flatMap { URL(string: $0) }
                }
                print("[GeoNudgeExt] Extracted URL from text: \(url?.absoluteString ?? "nil")")
                DispatchQueue.main.async { self?.store(url) }
            }
        } else {
            print("[GeoNudgeExt] ❌ No recognized attachment type — calling done()")
            done()
        }
    }

    private func store(_ url: URL?) {
        guard let url else {
            print("[GeoNudgeExt] ❌ store() called with nil URL")
            done(); return
        }
        print("[GeoNudgeExt] store() URL: \(url.absoluteString)")
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            print("[GeoNudgeExt] ❌ App Group container not found — enable App Groups in Signing & Capabilities")
            done(); return
        }
        print("[GeoNudgeExt] Container path: \(container.path)")
        let file = container.appendingPathComponent(pendingURLKey)
        do {
            try url.absoluteString.write(to: file, atomically: true, encoding: .utf8)
            print("[GeoNudgeExt] ✅ File written: \(file.path)")
            scheduleNotification()
        } catch {
            print("[GeoNudgeExt] ❌ File write error: \(error)")
        }
        print("[GeoNudgeExt] Calling done()")
        done()
    }

    // MARK: - Local notification as call-to-action

    private func scheduleNotification() {
        print("[GeoNudgeExt] Requesting notification permission + scheduling notification")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("[GeoNudgeExt] Notification auth status: \(settings.authorizationStatus.rawValue)")
        }

        let content = UNMutableNotificationContent()
        content.title = "Location Ready"
        content.body = "Tap to add it as a GeoNudge alert."
        content.sound = nil
        content.categoryIdentifier = "PENDING_IMPORT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "geonudge.pendingShare",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[GeoNudgeExt] ❌ Notification scheduling error: \(error)")
            } else {
                print("[GeoNudgeExt] ✅ Notification scheduled")
            }
        }
    }

    private func done() {
        print("[GeoNudgeExt] done() — completeRequest")
        extensionContext?.completeRequest(returningItems: nil)
    }
}
