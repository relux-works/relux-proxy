import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var terminationPending = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationPending else {
      return .terminateLater
    }

    terminationPending = true
    TunnelController.shared.shutdown {
      DispatchQueue.main.async {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
  }
}

@main
struct ReluxProxyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var controller = TunnelController.shared

  var body: some Scene {
    MenuBarExtra {
      MenuContentView(controller: controller)
    } label: {
      Image(systemName: controller.aggregateStatus.symbolName)
        .accessibilityLabel("Relux Proxy: \(controller.aggregateStatus.title)")
    }
    .menuBarExtraStyle(.window)
  }
}
