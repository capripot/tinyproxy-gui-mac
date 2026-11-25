import AppKit
import Foundation

/// Online status reporting through a StatusCake push test.
///
/// StatusCake marks a push test as down when it receives no push within the test's period,
/// so the app pushes only after a check finds tinyproxy running. When tinyproxy stops,
/// the pushes stop and StatusCake reports it down. See
/// https://www.statuscake.com/kb/knowledge-base/what-is-push-monitoring/
enum StatusCake {
    static let pushURLKey = "statusCakePushURL"

    /// The push URL as saved in the preferences, if reporting is on.
    static var savedPushURL: URL? {
        UserDefaults.standard.string(forKey: pushURLKey).flatMap(validatedPushURL)
    }

    /// Returns the URL if it looks like a push URL: https, with the `PK` and `TestID` parameters.
    static func validatedPushURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              let items = components.queryItems,
              items.contains(where: { $0.name == "PK" && $0.value?.isEmpty == false }),
              items.contains(where: { $0.name == "TestID" && $0.value?.isEmpty == false })
        else { return nil }
        return components.url
    }

    /// Sends one push. StatusCake answers errors with a 4xx status and `{"error": "..."}`.
    static func push(to url: URL) async throws {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct ErrorBody: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw StatusCakeError.rejected(status: status, message: message)
        }
    }
}

enum StatusCakeError: LocalizedError {
    case rejected(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case let .rejected(status, message?): "StatusCake: \(message) (HTTP \(status))"
        case let .rejected(status, nil): "StatusCake returned HTTP \(status)"
        }
    }
}

/// The "Configure Online Status Reporting…" dialog. An AppKit alert rather than a SwiftUI sheet,
/// so it also works from the menu bar icon while the window is closed.
@MainActor
enum StatusReportingDialog {
    static let menuTitle = "Configure Online Status Reporting…"

    static func present(for monitor: TinyproxyMonitor) {
        NSApp.activate(ignoringOtherApps: true)
        var text = monitor.pushURL?.absoluteString ?? ""

        while true {
            let alert = NSAlert()
            alert.messageText = "Online Status Reporting"
            alert.informativeText = """
                Paste the Push URL of a StatusCake push test.

                Set the push test's period to at least 2 minutes.
                """
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
            field.placeholderString = "https://push.statuscake.com/?PK=…&TestID=…&time=0"
            field.stringValue = text
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            if monitor.pushURL != nil {
                alert.addButton(withTitle: "Turn Off")
            }
            alert.window.initialFirstResponder = field

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    monitor.setPushURL(nil)
                    return
                }
                if let url = StatusCake.validatedPushURL(text) {
                    monitor.setPushURL(url)
                    return
                }
                let error = NSAlert()
                error.alertStyle = .warning
                error.messageText = "That doesn't look like a StatusCake Push URL"
                error.informativeText = "Copy it from the push test's page in StatusCake. It starts with https:// and contains PK= and TestID=."
                error.runModal()
            case .alertThirdButtonReturn:
                monitor.setPushURL(nil)
                return
            default:
                return
            }
        }
    }
}
