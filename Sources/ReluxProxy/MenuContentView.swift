import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var controller: TunnelController

    @AppStorage("sshHost") private var host = "relux"
    @AppStorage("sshAccount") private var account = "administrator"
    @AppStorage("localPort") private var localPort = 1_080

    private var configuration: TunnelConfiguration {
        TunnelConfiguration(host: host, account: account, localPort: localPort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: controller.status.symbolName)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: isTransitioning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Relux Proxy")
                        .font(.headline)
                    Text(controller.status.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("SSH host")
                    TextField("relux", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Account")
                    TextField("administrator", text: $account)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("SOCKS port")
                    TextField("1080", value: $localPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .disabled(controller.status.preventsEditing)

            HStack {
                Text("Proxy endpoint")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(configuration.localEndpoint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            if case let .failed(message) = controller.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let validationError = configuration.validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: toggleConnection) {
                HStack {
                    Spacer()
                    Text(connectionButtonTitle)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(connectionButtonDisabled)

            Divider()

            HStack {
                Text("Firefox: SOCKS v5 + proxy DNS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    controller.shutdown()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var isTransitioning: Bool {
        controller.status == .connecting || controller.status == .disconnecting
    }

    private var statusColor: Color {
        switch controller.status {
        case .disconnected: .secondary
        case .connecting, .disconnecting: .orange
        case .connected: .green
        case .failed: .red
        }
    }

    private var connectionButtonTitle: String {
        switch controller.status {
        case .disconnected, .failed: "Connect"
        case .connecting: "Connecting…"
        case .connected: "Disconnect"
        case .disconnecting: "Disconnecting…"
        }
    }

    private var connectionButtonDisabled: Bool {
        switch controller.status {
        case .connecting, .disconnecting:
            true
        case .disconnected, .failed:
            configuration.validationError != nil
        case .connected:
            false
        }
    }

    private func toggleConnection() {
        if controller.status.isConnected {
            controller.disconnect()
        } else {
            controller.connect(configuration: configuration)
        }
    }
}
