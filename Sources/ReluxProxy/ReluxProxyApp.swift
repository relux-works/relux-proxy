import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        TunnelController.shared.shutdown()
    }
}

@main
struct ReluxProxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = TunnelController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller)
        } label: {
            Image(systemName: controller.status.symbolName)
                .accessibilityLabel("Relux Proxy: \(controller.status.title)")
        }
        .menuBarExtraStyle(.window)
    }
}
