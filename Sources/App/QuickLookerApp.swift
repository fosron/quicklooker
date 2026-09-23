import SwiftUI

@main
struct QuickLookerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("QuickLooker", id: "main") {
            SetupView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Extension Status") {
                    NotificationCenter.default.post(name: .refreshExtensionStatus, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
                Divider()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let refreshExtensionStatus = Notification.Name("QuickLookerRefreshExtensionStatus")
}
