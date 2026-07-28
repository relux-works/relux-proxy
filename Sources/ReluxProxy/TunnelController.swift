import Foundation
import Observation

enum TunnelStatus: Equatable, Sendable {
  case disconnected
  case connecting
  case connected
  case disconnecting
  case failed(String)

  var title: String {
    switch self {
    case .disconnected: "Disconnected"
    case .connecting: "Connecting…"
    case .connected: "Connected"
    case .disconnecting: "Disconnecting…"
    case .failed: "Connection failed"
    }
  }

  var symbolName: String {
    switch self {
    case .disconnected: "network.slash"
    case .connecting, .disconnecting: "ellipsis.circle"
    case .connected: "network"
    case .failed: "exclamationmark.triangle"
    }
  }

  var isTransitioning: Bool {
    self == .connecting || self == .disconnecting
  }

  var failureMessage: String? {
    guard case .failed(let message) = self else {
      return nil
    }
    return message
  }
}

struct TunnelAggregateStatus: Equatable {
  let title: String
  let symbolName: String

  static func summarize(_ statuses: [TunnelStatus]) -> TunnelAggregateStatus {
    let failedCount = statuses.count { status in
      if case .failed = status {
        return true
      }
      return false
    }
    let connectedCount = statuses.count { $0 == .connected }
    let connectingCount = statuses.count { $0 == .connecting }
    let disconnectingCount = statuses.count { $0 == .disconnecting }

    if failedCount > 0 {
      var parts: [String] = []
      if connectedCount > 0 {
        parts.append("\(connectedCount) connected")
      }
      if connectingCount > 0 {
        parts.append("\(connectingCount) connecting")
      }
      if disconnectingCount > 0 {
        parts.append("\(disconnectingCount) disconnecting")
      }
      parts.append(failedCount == 1 ? "1 failed" : "\(failedCount) failed")
      return TunnelAggregateStatus(
        title: parts.joined(separator: ", "),
        symbolName: "exclamationmark.triangle"
      )
    }
    if connectedCount > 0 {
      var parts = [
        connectedCount == 1
          ? "1 tunnel connected"
          : "\(connectedCount) tunnels connected"
      ]
      if connectingCount > 0 {
        parts.append("\(connectingCount) connecting")
      }
      if disconnectingCount > 0 {
        parts.append("\(disconnectingCount) disconnecting")
      }
      return TunnelAggregateStatus(
        title: parts.joined(separator: ", "),
        symbolName: "network"
      )
    }
    if connectingCount > 0 {
      let title =
        connectingCount == 1
        ? "1 tunnel connecting"
        : "\(connectingCount) tunnels connecting"
      return TunnelAggregateStatus(title: title, symbolName: "ellipsis.circle")
    }
    if disconnectingCount > 0 {
      let title =
        disconnectingCount == 1
        ? "1 tunnel disconnecting"
        : "\(disconnectingCount) tunnels disconnecting"
      return TunnelAggregateStatus(title: title, symbolName: "ellipsis.circle")
    }
    return TunnelAggregateStatus(title: "No tunnels connected", symbolName: "network.slash")
  }
}

@MainActor
@Observable
final class TunnelSession: Identifiable {
  let id: UUID
  fileprivate(set) var status: TunnelStatus = .disconnected
  fileprivate(set) var diagnostic = ""
  fileprivate(set) var isActive = false

  @ObservationIgnored fileprivate var generation: UInt64 = 0
  @ObservationIgnored fileprivate var process: TunnelProcessHandle?
  @ObservationIgnored fileprivate var readiness: TunnelCancellation?
  @ObservationIgnored fileprivate var forceStopAction: TunnelCancellation?
  @ObservationIgnored fileprivate var configurationSnapshot: TunnelConfiguration?
  @ObservationIgnored fileprivate var requestedStop = false

  init(profileID: UUID) {
    id = profileID
  }

  var preventsProfileChanges: Bool {
    isActive
  }

  var isCleaningUpFailedProcess: Bool {
    isActive && status.failureMessage != nil
  }
}

@MainActor
@Observable
final class TunnelController {
  static let shared = TunnelController()

  private static let maximumDiagnosticLength = 4_000
  private static let stopGracePeriod: TimeInterval = 2

  private(set) var profiles: [TunnelProfile]
  let persistenceError: String?
  let migrationDiagnostic: String?

  @ObservationIgnored private let store: TunnelProfileStore
  @ObservationIgnored private let processFactory: TunnelProcessFactory
  @ObservationIgnored private let portProbe: LocalPortProbing
  @ObservationIgnored private let readinessMonitor: TunnelReadinessMonitoring
  @ObservationIgnored private let scheduler: TunnelScheduling
  @ObservationIgnored private var sessions: [UUID: TunnelSession]
  @ObservationIgnored private var isShuttingDown = false
  @ObservationIgnored private var shutdownCompletions: [@MainActor () -> Void] = []

  init(
    store: TunnelProfileStore = TunnelProfileStore(),
    processFactory: TunnelProcessFactory = SystemTunnelProcessFactory(),
    portProbe: LocalPortProbing = SystemLocalPortProbe(),
    readinessMonitor: TunnelReadinessMonitoring? = nil,
    scheduler: TunnelScheduling = DispatchTunnelScheduler()
  ) {
    self.store = store
    self.processFactory = processFactory
    self.portProbe = portProbe
    self.readinessMonitor =
      readinessMonitor
      ?? PollingTunnelReadinessMonitor(portProbe: portProbe)
    self.scheduler = scheduler
    profiles = store.profiles
    persistenceError = store.blockingError
    migrationDiagnostic = store.migrationDiagnostic
    sessions = Dictionary(
      uniqueKeysWithValues: store.profiles.map { profile in
        (profile.id, TunnelSession(profileID: profile.id))
      }
    )
  }

  var aggregateStatus: TunnelAggregateStatus {
    TunnelAggregateStatus.summarize(
      profiles.compactMap { sessions[$0.id]?.status }
    )
  }

  func session(for profileID: UUID) -> TunnelSession? {
    sessions[profileID]
  }

  @discardableResult
  func addProfile(host: String, account: String, localPort: Int) throws -> TunnelProfile {
    let profile = try store.addProfile(host: host, account: account, localPort: localPort)
    profiles = store.profiles
    sessions[profile.id] = TunnelSession(profileID: profile.id)
    return profile
  }

  @discardableResult
  func updateProfile(_ profile: TunnelProfile) throws -> TunnelProfile {
    try requireInactiveProfile(profile.id)
    let updatedProfile = try store.updateProfile(profile)
    profiles = store.profiles
    return updatedProfile
  }

  func removeProfile(id: UUID) throws {
    try requireInactiveProfile(id)
    try store.removeProfile(id: id)
    profiles = store.profiles
    sessions.removeValue(forKey: id)
  }

  func connect(profileID: UUID) {
    guard !isShuttingDown,
      let profile = profiles.first(where: { $0.id == profileID }),
      let session = sessions[profileID],
      !session.isActive
    else {
      return
    }

    let configuration = profile.configuration
    beginConnectionAttempt(session, configuration: configuration)
    let generation = session.generation

    do {
      let arguments = try SSHCommandBuilder.arguments(for: configuration)

      if sessions.values.contains(where: { otherSession in
        otherSession.id != profileID
          && otherSession.isActive
          && otherSession.configurationSnapshot?.localPort == configuration.localPort
      }) {
        throw TunnelLaunchError.portReserved(configuration.localEndpoint)
      }

      guard portProbe.isAvailable(configuration.localPort) else {
        throw TunnelLaunchError.localPortInUse(configuration.localEndpoint)
      }

      let process = processFactory.makeProcess()
      session.process = process
      try process.run(
        executableURL: SSHCommandBuilder.executableURL,
        arguments: arguments,
        stderrHandler: { [weak self, weak process] text in
          guard let process else {
            return
          }
          self?.handleStderr(
            text,
            profileID: profileID,
            generation: generation,
            process: process
          )
        },
        terminationHandler: { [weak self, weak process] exitStatus in
          guard let process else {
            return
          }
          self?.handleTermination(
            exitStatus: exitStatus,
            profileID: profileID,
            generation: generation,
            process: process
          )
        }
      )

      guard
        currentSession(
          profileID: profileID,
          generation: generation,
          process: process
        ) != nil, process.isRunning
      else {
        return
      }

      session.readiness = readinessMonitor.monitor(
        process: process,
        port: configuration.localPort
      ) { [weak self, weak process] result in
        guard let process else {
          return
        }
        self?.handleReadiness(
          result,
          profileID: profileID,
          generation: generation,
          process: process
        )
      }
    } catch {
      guard let current = sessions[profileID], current.generation == generation else {
        return
      }
      recordStartFailure(error, in: current)
    }
  }

  func disconnect(profileID: UUID) {
    guard let session = sessions[profileID],
      session.isActive,
      session.status != .disconnecting,
      !session.isCleaningUpFailedProcess
    else {
      return
    }
    guard let process = session.process else {
      clearRuntime(session)
      session.diagnostic = ""
      session.status = .disconnected
      finishShutdownIfPossible()
      return
    }

    session.requestedStop = true
    session.status = .disconnecting
    session.readiness?.cancel()
    session.readiness = nil
    process.terminate()
    scheduleForcedStop(
      for: session,
      process: process,
      generation: session.generation
    )
  }

  func shutdown(completion: @escaping @MainActor () -> Void = {}) {
    shutdownCompletions.append(completion)
    isShuttingDown = true

    let activeProfileIDs = sessions.values
      .filter(\.isActive)
      .map(\.id)
    for profileID in activeProfileIDs {
      disconnect(profileID: profileID)
    }
    finishShutdownIfPossible()
  }

  private func requireInactiveProfile(_ profileID: UUID) throws {
    guard profiles.contains(where: { $0.id == profileID }) else {
      throw TunnelProfileError.profileNotFound(profileID)
    }
    if sessions[profileID]?.preventsProfileChanges == true {
      throw TunnelProfileError.activeProfile(profileID)
    }
  }

  private func beginConnectionAttempt(
    _ session: TunnelSession,
    configuration: TunnelConfiguration
  ) {
    session.generation &+= 1
    session.status = .connecting
    session.diagnostic = ""
    session.isActive = true
    session.configurationSnapshot = configuration
    session.requestedStop = false
    session.readiness?.cancel()
    session.readiness = nil
    session.forceStopAction?.cancel()
    session.forceStopAction = nil
    session.process?.invalidateCallbacks()
    session.process = nil
  }

  private func handleStderr(
    _ text: String,
    profileID: UUID,
    generation: UInt64,
    process: TunnelProcessHandle
  ) {
    guard
      let session = currentSession(
        profileID: profileID,
        generation: generation,
        process: process
      )
    else {
      return
    }
    appendDiagnostic(text, to: session)
  }

  private func handleReadiness(
    _ result: TunnelReadinessResult,
    profileID: UUID,
    generation: UInt64,
    process: TunnelProcessHandle
  ) {
    guard
      let session = currentSession(
        profileID: profileID,
        generation: generation,
        process: process
      ), session.status == .connecting, !session.requestedStop, process.isRunning
    else {
      return
    }

    session.readiness?.cancel()
    session.readiness = nil

    switch result {
    case .ready:
      session.status = .connected
    case .timedOut:
      let endpoint = session.configurationSnapshot?.localEndpoint ?? "the local SOCKS endpoint"
      let message = "Timed out waiting for \(endpoint) to accept connections."
      appendDiagnostic(message, to: session)
      session.status = .failed(message)
      process.terminate()
      scheduleForcedStop(for: session, process: process, generation: generation)
    }
  }

  private func handleTermination(
    exitStatus: Int32,
    profileID: UUID,
    generation: UInt64,
    process: TunnelProcessHandle
  ) {
    guard
      let session = currentSession(
        profileID: profileID,
        generation: generation,
        process: process
      )
    else {
      return
    }

    let stoppedByUser = session.requestedStop
    let fallback = "SSH exited with status \(exitStatus)."
    let summary = lastNonEmptyDiagnosticLine(in: session.diagnostic) ?? fallback
    clearRuntime(session)

    if stoppedByUser {
      session.diagnostic = ""
      session.status = .disconnected
    } else {
      if session.diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        session.diagnostic = fallback
      }
      session.status = .failed(summary)
    }
    finishShutdownIfPossible()
  }

  private func recordStartFailure(_ error: Error, in session: TunnelSession) {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    clearRuntime(session)
    appendDiagnostic(message, to: session)
    session.status = .failed(message)
    finishShutdownIfPossible()
  }

  private func scheduleForcedStop(
    for session: TunnelSession,
    process: TunnelProcessHandle,
    generation: UInt64
  ) {
    session.forceStopAction?.cancel()
    session.forceStopAction = scheduler.schedule(after: Self.stopGracePeriod) {
      guard
        let current = self.currentSession(
          profileID: session.id,
          generation: generation,
          process: process
        ), current.isActive, process.isRunning
      else {
        return
      }
      process.forceTerminate()
    }
  }

  private func currentSession(
    profileID: UUID,
    generation: UInt64,
    process: TunnelProcessHandle
  ) -> TunnelSession? {
    guard let session = sessions[profileID],
      session.generation == generation,
      session.process === process
    else {
      return nil
    }
    return session
  }

  private func clearRuntime(_ session: TunnelSession) {
    session.readiness?.cancel()
    session.readiness = nil
    session.forceStopAction?.cancel()
    session.forceStopAction = nil
    session.process?.invalidateCallbacks()
    session.process = nil
    session.configurationSnapshot = nil
    session.requestedStop = false
    session.isActive = false
  }

  private func appendDiagnostic(_ text: String, to session: TunnelSession) {
    session.diagnostic += text
    if session.diagnostic.count > Self.maximumDiagnosticLength {
      session.diagnostic = String(
        session.diagnostic.suffix(Self.maximumDiagnosticLength)
      )
    }
  }

  private func lastNonEmptyDiagnosticLine(in diagnostic: String) -> String? {
    diagnostic
      .split(whereSeparator: \Character.isNewline)
      .map { line in
        String(line).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      .last(where: { !$0.isEmpty })
  }

  private func finishShutdownIfPossible() {
    guard isShuttingDown, !sessions.values.contains(where: \.isActive) else {
      return
    }

    let completions = shutdownCompletions
    shutdownCompletions.removeAll()
    for completion in completions {
      completion()
    }
  }
}

private enum TunnelLaunchError: LocalizedError {
  case portReserved(String)
  case localPortInUse(String)

  var errorDescription: String? {
    switch self {
    case .portReserved(let endpoint):
      "Local endpoint \(endpoint) is already reserved by another Relux Proxy profile."
    case .localPortInUse(let endpoint):
      "Local endpoint \(endpoint) is already in use. Stop its owner or choose a different port."
    }
  }
}
