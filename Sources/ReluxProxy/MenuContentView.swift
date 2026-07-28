import AppKit
import SwiftUI

struct MenuContentView: View {
  let controller: TunnelController

  @State private var editorRoute: ProfileEditorRoute?
  @State private var operationError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      TunnelSummaryHeader(controller: controller)

      Divider()

      HStack {
        Text("SOCKS profiles")
          .font(.headline)
        Spacer()
        Button {
          editorRoute = .add
        } label: {
          Label("Add profile", systemImage: "plus")
        }
        .accessibilityLabel("Add SSH SOCKS profile")
        .disabled(controller.persistenceError != nil)
      }

      if let persistenceError = controller.persistenceError {
        MessageBanner(text: persistenceError, color: .red)
      } else if let migrationDiagnostic = controller.migrationDiagnostic {
        MessageBanner(text: migrationDiagnostic, color: .orange)
      }

      if controller.profiles.isEmpty {
        ContentUnavailableView(
          "No SOCKS Profiles",
          systemImage: "network.slash",
          description: Text("Add a profile to create a local SSH SOCKS endpoint.")
        )
        .frame(maxWidth: .infinity, minHeight: 150)
      } else {
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(controller.profiles) { profile in
              TunnelProfileRow(
                profile: profile,
                session: controller.session(for: profile.id),
                controller: controller,
                onEdit: {
                  editorRoute = .edit(profile)
                },
                onRemove: {
                  remove(profile)
                }
              )
            }
          }
          .padding(.vertical, 1)
        }
        .frame(maxHeight: 390)
      }

      if let operationError {
        MessageBanner(text: operationError, color: .red)
      }

      Divider()

      HStack {
        Text(TunnelGuidance.clientHint)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Quit") {
          NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
        .accessibilityLabel("Quit Relux Proxy and disconnect all tunnels")
      }
    }
    .padding(16)
    .frame(width: 470)
    .sheet(item: $editorRoute) { route in
      ProfileEditorView(controller: controller, route: route)
    }
  }

  private func remove(_ profile: TunnelProfile) {
    do {
      try controller.removeProfile(id: profile.id)
      operationError = nil
    } catch {
      operationError = error.userFacingMessage
    }
  }
}

private struct TunnelSummaryHeader: View {
  let controller: TunnelController

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: controller.aggregateStatus.symbolName)
        .font(.title2)
        .foregroundStyle(statusColor)
        .symbolEffect(.pulse, isActive: hasTransitioningSession)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text("Relux Proxy")
          .font(.headline)
        Text(controller.aggregateStatus.title)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Relux Proxy, \(controller.aggregateStatus.title)")
  }

  private var hasTransitioningSession: Bool {
    controller.profiles.contains { profile in
      controller.session(for: profile.id)?.status.isTransitioning == true
    }
  }

  private var statusColor: Color {
    switch controller.aggregateStatus.symbolName {
    case "exclamationmark.triangle": .red
    case "network": .green
    case "ellipsis.circle": .orange
    default: .secondary
    }
  }
}

private struct TunnelProfileRow: View {
  let profile: TunnelProfile
  let session: TunnelSession?
  let controller: TunnelController
  let onEdit: () -> Void
  let onRemove: () -> Void

  @State private var showsDiagnostics = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: status.symbolName)
          .foregroundStyle(statusColor)
          .symbolEffect(.pulse, isActive: status.isTransitioning)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 3) {
          Text(profile.displayTarget)
            .font(.body.weight(.medium))
          Text(TunnelGuidance.endpointLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Text(profile.configuration.localEndpoint)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          Text(status.title)
            .font(.caption)
            .foregroundStyle(statusColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          "\(profile.displayTarget), \(TunnelGuidance.endpointLabel) \(profile.configuration.localEndpoint), \(status.title)"
        )

        Spacer()

        Button {
          onEdit()
        } label: {
          Label("Edit", systemImage: "pencil")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Edit \(profile.displayTarget)")
        .disabled(preventsProfileChanges)

        Button(role: .destructive) {
          onRemove()
        } label: {
          Label("Remove", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Remove \(profile.displayTarget)")
        .disabled(preventsProfileChanges)
      }

      if let diagnostic = session?.diagnostic, !diagnostic.isEmpty {
        DisclosureGroup("Diagnostics", isExpanded: $showsDiagnostics) {
          Text(diagnostic)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .accessibilityLabel("Diagnostics for \(profile.displayTarget)")
      }

      Button(action: toggleConnection) {
        Text(lifecycleButtonTitle)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(lifecycleButtonDisabled)
      .accessibilityLabel("\(lifecycleButtonTitle) \(profile.displayTarget)")
    }
    .padding(12)
    .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
  }

  private var status: TunnelStatus {
    session?.status ?? .failed("Runtime state is unavailable.")
  }

  private var preventsProfileChanges: Bool {
    session?.preventsProfileChanges ?? true
  }

  private var statusColor: Color {
    switch status {
    case .disconnected: .secondary
    case .connecting, .disconnecting: .orange
    case .connected: .green
    case .failed: .red
    }
  }

  private var lifecycleButtonTitle: String {
    guard session?.isActive == true else {
      return "Connect"
    }
    switch status {
    case .connecting: return "Cancel"
    case .connected: return "Disconnect"
    case .disconnecting: return "Disconnecting…"
    case .failed: return "Cleaning up…"
    case .disconnected: return "Disconnect"
    }
  }

  private var lifecycleButtonDisabled: Bool {
    session == nil
      || status == .disconnecting
      || session?.isCleaningUpFailedProcess == true
  }

  private func toggleConnection() {
    guard let session else {
      return
    }
    if session.isActive {
      controller.disconnect(profileID: profile.id)
    } else {
      controller.connect(profileID: profile.id)
    }
  }
}

private struct MessageBanner: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(text)
  }
}

private enum ProfileEditorRoute: Identifiable {
  case add
  case edit(TunnelProfile)

  var id: String {
    switch self {
    case .add: "add"
    case .edit(let profile): "edit-\(profile.id.uuidString)"
    }
  }

  var profile: TunnelProfile? {
    guard case .edit(let profile) = self else {
      return nil
    }
    return profile
  }
}

private struct ProfileEditorView: View {
  @Environment(\.dismiss) private var dismiss

  let controller: TunnelController
  let route: ProfileEditorRoute

  @State private var host: String
  @State private var account: String
  @State private var localPortText: String
  @State private var validationMessage: String?

  init(controller: TunnelController, route: ProfileEditorRoute) {
    self.controller = controller
    self.route = route

    let profile = route.profile
    _host = State(initialValue: profile?.host ?? "relux")
    _account = State(initialValue: profile?.account ?? "")
    _localPortText = State(initialValue: String(profile?.localPort ?? 1_080))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(route.profile == nil ? "Add SOCKS Profile" : "Edit SOCKS Profile")
        .font(.title2)

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
        GridRow {
          Text("SSH host")
          TextField("Host, address, or OpenSSH alias", text: $host)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("SSH host or OpenSSH alias")
        }
        GridRow {
          Text("Account")
          TextField("Optional account override", text: $account)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Optional SSH account override")
        }
        GridRow {
          Text("SOCKS port")
          TextField("1080", text: $localPortText)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Local SOCKS port")
        }
      }

      Text("Leave Account empty to use OpenSSH configuration or its normal login-user default.")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let validationMessage {
        MessageBanner(text: validationMessage, color: .red)
      }

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Save") {
          save()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 430)
  }

  private func save() {
    guard let localPort = Int(localPortText) else {
      validationMessage = "The local port must be a whole number between 1 and 65535."
      return
    }

    do {
      if let existingProfile = route.profile {
        try controller.updateProfile(
          TunnelProfile(
            id: existingProfile.id,
            host: host,
            account: account,
            localPort: localPort
          )
        )
      } else {
        try controller.addProfile(host: host, account: account, localPort: localPort)
      }
      dismiss()
    } catch {
      validationMessage = error.userFacingMessage
    }
  }
}

extension Error {
  fileprivate var userFacingMessage: String {
    (self as? LocalizedError)?.errorDescription ?? localizedDescription
  }
}
