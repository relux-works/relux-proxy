import Foundation
import Testing

@testable import ReluxProxy

@MainActor
@Suite
struct TunnelControllerTests {
  @Test
  func aggregateStatusSummarizesZeroSomeAndFailedConnections() {
    #expect(
      TunnelAggregateStatus.summarize([])
        == TunnelAggregateStatus(title: "No tunnels connected", symbolName: "network.slash")
    )
    #expect(
      TunnelAggregateStatus.summarize([.connected, .connecting, .disconnected])
        == TunnelAggregateStatus(
          title: "1 tunnel connected, 1 connecting",
          symbolName: "network"
        )
    )
    #expect(
      TunnelAggregateStatus.summarize([.connected, .failed("failure")])
        == TunnelAggregateStatus(
          title: "1 connected, 1 failed", symbolName: "exclamationmark.triangle")
    )
  }

  @Test
  func runsConcurrentSessionsWithIndependentStateAndDiagnostics() throws {
    let fixture = try ControllerFixture(
      profiles: [
        ("alpha", 1_080),
        ("beta", 1_081),
      ]
    )
    defer { fixture.cleanup() }
    let first = fixture.profiles[0]
    let second = fixture.profiles[1]

    fixture.controller.connect(profileID: first.id)
    fixture.controller.connect(profileID: second.id)

    #expect(fixture.processFactory.processes.count == 2)
    let firstProcess = fixture.processFactory.processes[0]
    let secondProcess = fixture.processFactory.processes[1]
    #expect(firstProcess.arguments.contains("127.0.0.1:1080"))
    #expect(secondProcess.arguments.contains("127.0.0.1:1081"))
    #expect(fixture.controller.session(for: first.id)?.status == .connecting)
    #expect(fixture.controller.session(for: second.id)?.status == .connecting)

    fixture.readinessMonitor.send(.ready, observation: 0)
    fixture.readinessMonitor.send(.ready, observation: 1)
    firstProcess.emitStderr(String(repeating: "a", count: 4_500))
    secondProcess.emitStderr("beta failure\n   \n")

    let firstSession = try #require(fixture.controller.session(for: first.id))
    let secondSession = try #require(fixture.controller.session(for: second.id))
    #expect(firstSession.status == .connected)
    #expect(secondSession.status == .connected)
    #expect(firstSession.diagnostic.count == 4_000)
    #expect(secondSession.diagnostic == "beta failure\n   \n")

    secondProcess.emitTermination(status: 17)

    #expect(secondSession.status == .failed("beta failure"))
    #expect(!secondSession.isActive)
    #expect(firstSession.status == .connected)
    #expect(firstSession.isActive)
    #expect(firstProcess.isRunning)
    #expect(fixture.controller.aggregateStatus.title == "1 connected, 1 failed")

    fixture.controller.disconnect(profileID: first.id)
    #expect(firstSession.status == .disconnecting)
    #expect(firstProcess.terminateCallCount == 1)
    #expect(secondSession.status == .failed("beta failure"))

    firstProcess.emitTermination(status: 0)
    #expect(firstSession.status == .disconnected)
    #expect(firstSession.diagnostic.isEmpty)
    #expect(secondSession.status == .failed("beta failure"))
  }

  @Test
  func occupiedPortFailureDoesNotDisturbConnectedProfile() throws {
    let fixture = try ControllerFixture(
      profiles: [
        ("connected", 2_080),
        ("occupied", 2_081),
      ]
    )
    defer { fixture.cleanup() }
    let connected = fixture.profiles[0]
    let occupied = fixture.profiles[1]

    fixture.controller.connect(profileID: connected.id)
    fixture.readinessMonitor.send(.ready, observation: 0)
    fixture.controller.connect(profileID: connected.id)
    #expect(fixture.processFactory.processes.count == 1)

    fixture.portProbe.setUnavailable([occupied.localPort])
    fixture.controller.connect(profileID: occupied.id)

    let connectedSession = try #require(fixture.controller.session(for: connected.id))
    let occupiedSession = try #require(fixture.controller.session(for: occupied.id))
    #expect(connectedSession.status == .connected)
    #expect(connectedSession.isActive)
    #expect(fixture.processFactory.processes[0].isRunning)
    #expect(
      occupiedSession.status.failureMessage?
        .contains("127.0.0.1:2081") == true
    )
    #expect(!occupiedSession.isActive)
    #expect(fixture.processFactory.processes.count == 1)
  }

  @Test
  func lateCallbacksCannotChangeRestartedGeneration() throws {
    let fixture = try ControllerFixture(profiles: [("restartable", 3_080)])
    defer { fixture.cleanup() }
    let profile = fixture.profiles[0]

    fixture.controller.connect(profileID: profile.id)
    let oldProcess = fixture.processFactory.processes[0]
    fixture.controller.disconnect(profileID: profile.id)
    fixture.readinessMonitor.send(.ready, observation: 0)
    #expect(fixture.controller.session(for: profile.id)?.status == .disconnecting)
    oldProcess.emitTermination(status: 0)
    #expect(fixture.controller.session(for: profile.id)?.status == .disconnected)

    fixture.controller.connect(profileID: profile.id)
    let newProcess = fixture.processFactory.processes[1]
    let session = try #require(fixture.controller.session(for: profile.id))
    #expect(session.status == .connecting)

    oldProcess.emitStderr("stale stderr")
    oldProcess.emitTermination(status: 99)
    fixture.readinessMonitor.send(.ready, observation: 0)

    #expect(session.status == .connecting)
    #expect(session.diagnostic.isEmpty)
    #expect(session.isActive)
    #expect(newProcess.isRunning)

    fixture.readinessMonitor.send(.ready, observation: 1)
    #expect(session.status == .connected)
  }

  @Test
  func readinessTimeoutAndCleanupRemainIsolated() throws {
    let fixture = try ControllerFixture(
      profiles: [
        ("healthy", 4_080),
        ("timeout", 4_081),
      ]
    )
    defer { fixture.cleanup() }
    let healthy = fixture.profiles[0]
    let timeout = fixture.profiles[1]

    fixture.controller.connect(profileID: healthy.id)
    fixture.readinessMonitor.send(.ready, observation: 0)
    fixture.controller.connect(profileID: timeout.id)
    fixture.readinessMonitor.send(.timedOut, observation: 1)

    let healthySession = try #require(fixture.controller.session(for: healthy.id))
    let timeoutSession = try #require(fixture.controller.session(for: timeout.id))
    #expect(healthySession.status == .connected)
    #expect(timeoutSession.status.failureMessage?.contains("Timed out") == true)
    #expect(timeoutSession.isActive)
    #expect(fixture.processFactory.processes[1].terminateCallCount == 1)
    #expect(throws: TunnelProfileError.activeProfile(timeout.id)) {
      try fixture.controller.removeProfile(id: timeout.id)
    }

    fixture.processFactory.processes[1].emitTermination(status: 255)

    #expect(timeoutSession.status.failureMessage?.contains("Timed out") == true)
    #expect(!timeoutSession.isActive)
    #expect(healthySession.status == .connected)
    try fixture.controller.removeProfile(id: timeout.id)
    #expect(fixture.controller.profiles.map(\.id) == [healthy.id])
    #expect(healthySession.status == .connected)
  }

  @Test
  func readinessFailureCannotBeClearedBeforeExplicitRestart() throws {
    let fixture = try ControllerFixture(profiles: [("retry", 4_180)])
    defer { fixture.cleanup() }
    let profile = fixture.profiles[0]

    fixture.controller.connect(profileID: profile.id)
    let failedProcess = fixture.processFactory.processes[0]
    failedProcess.emitStderr("SSH setup failed\n")
    fixture.readinessMonitor.send(.timedOut, observation: 0)

    let session = try #require(fixture.controller.session(for: profile.id))
    let failedStatus = session.status
    let failedDiagnostic = session.diagnostic
    #expect(failedStatus.failureMessage?.contains("Timed out") == true)
    #expect(failedDiagnostic.contains("SSH setup failed"))
    #expect(session.isActive)
    #expect(session.isCleaningUpFailedProcess)

    fixture.controller.disconnect(profileID: profile.id)

    #expect(session.status == failedStatus)
    #expect(session.diagnostic == failedDiagnostic)
    #expect(session.isActive)
    #expect(failedProcess.terminateCallCount == 1)
    #expect(fixture.scheduler.actions.count == 1)

    failedProcess.emitTermination(status: 255)

    #expect(session.status == failedStatus)
    #expect(session.diagnostic == failedDiagnostic)
    #expect(!session.isActive)
    #expect(!session.isCleaningUpFailedProcess)

    fixture.controller.connect(profileID: profile.id)
    #expect(fixture.processFactory.processes.count == 2)
    #expect(fixture.readinessMonitor.observations.count == 2)
    let retryProcess = try #require(fixture.processFactory.processes.last)

    #expect(session.status == .connecting)
    #expect(session.diagnostic.isEmpty)
    #expect(session.isActive)
    #expect(!session.isCleaningUpFailedProcess)
    #expect(retryProcess !== failedProcess)
    #expect(retryProcess.isRunning)

    failedProcess.emitStderr("stale diagnostic")
    failedProcess.emitTermination(status: 99)

    #expect(session.status == .connecting)
    #expect(session.diagnostic.isEmpty)
    #expect(session.isActive)
    #expect(retryProcess.isRunning)

    fixture.readinessMonitor.send(.ready, observation: 1)
    #expect(session.status == .connected)
  }

  @Test
  func shutdownWaitsForFailedReadinessCleanupWithoutErasingFailure() throws {
    let fixture = try ControllerFixture(profiles: [("quit-failure", 4_280)])
    defer { fixture.cleanup() }
    let profile = fixture.profiles[0]

    fixture.controller.connect(profileID: profile.id)
    let failedProcess = fixture.processFactory.processes[0]
    failedProcess.emitStderr("Failure retained during quit\n")
    fixture.readinessMonitor.send(.timedOut, observation: 0)

    let session = try #require(fixture.controller.session(for: profile.id))
    let failedStatus = session.status
    let failedDiagnostic = session.diagnostic
    var shutdownCompleted = false

    fixture.controller.shutdown {
      shutdownCompleted = true
    }

    #expect(!shutdownCompleted)
    #expect(session.status == failedStatus)
    #expect(session.diagnostic == failedDiagnostic)
    #expect(session.isActive)
    #expect(session.isCleaningUpFailedProcess)
    #expect(failedProcess.terminateCallCount == 1)

    fixture.scheduler.run(action: 0)

    #expect(!shutdownCompleted)
    #expect(failedProcess.forceTerminateCallCount == 1)
    #expect(session.status == failedStatus)
    #expect(session.diagnostic == failedDiagnostic)

    failedProcess.emitTermination(status: 255)

    #expect(shutdownCompleted)
    #expect(session.status == failedStatus)
    #expect(session.diagnostic == failedDiagnostic)
    #expect(!session.isActive)
    #expect(!session.isCleaningUpFailedProcess)
  }

  @Test
  func activeProfilesRejectEditsAndRemovalUntilStopped() throws {
    let fixture = try ControllerFixture(profiles: [("immutable", 5_080)])
    defer { fixture.cleanup() }
    let profile = fixture.profiles[0]

    fixture.controller.connect(profileID: profile.id)
    let edited = TunnelProfile(
      id: profile.id,
      host: "edited",
      account: "ops",
      localPort: 5_081
    )

    #expect(throws: TunnelProfileError.activeProfile(profile.id)) {
      try fixture.controller.updateProfile(edited)
    }
    #expect(throws: TunnelProfileError.activeProfile(profile.id)) {
      try fixture.controller.removeProfile(id: profile.id)
    }
    #expect(fixture.controller.profiles == [profile])

    fixture.controller.disconnect(profileID: profile.id)
    fixture.scheduler.run(action: 0)
    #expect(fixture.processFactory.processes[0].forceTerminateCallCount == 1)
    fixture.processFactory.processes[0].emitTermination(status: 0)
    let saved = try fixture.controller.updateProfile(edited)

    #expect(saved.id == profile.id)
    #expect(saved.host == "edited")
    #expect(saved.localPort == 5_081)
  }

  @Test
  func shutdownStopsEveryOwnedChildAndWaitsForTheirTermination() throws {
    let fixture = try ControllerFixture(
      profiles: [
        ("first", 6_080),
        ("second", 6_081),
      ]
    )
    defer { fixture.cleanup() }
    let first = fixture.profiles[0]
    let second = fixture.profiles[1]

    fixture.controller.connect(profileID: first.id)
    fixture.controller.connect(profileID: second.id)
    fixture.processFactory.processes[0].emitStderr("first diagnostic")
    fixture.processFactory.processes[1].emitStderr("second diagnostic")
    var shutdownCompleted = false

    fixture.controller.shutdown {
      shutdownCompleted = true
    }

    #expect(!shutdownCompleted)
    #expect(fixture.processFactory.processes.allSatisfy { $0.terminateCallCount == 1 })
    #expect(fixture.scheduler.actions.count == 2)
    #expect(fixture.controller.session(for: first.id)?.status == .disconnecting)
    #expect(fixture.controller.session(for: second.id)?.status == .disconnecting)

    fixture.processFactory.processes[0].emitTermination(status: 0)
    #expect(!shutdownCompleted)
    fixture.processFactory.processes[1].emitTermination(status: 0)

    #expect(shutdownCompleted)
    #expect(fixture.controller.session(for: first.id)?.status == .disconnected)
    #expect(fixture.controller.session(for: second.id)?.status == .disconnected)
    #expect(fixture.controller.session(for: first.id)?.diagnostic.isEmpty == true)
    #expect(fixture.controller.session(for: second.id)?.diagnostic.isEmpty == true)

    fixture.controller.connect(profileID: first.id)
    #expect(fixture.processFactory.processes.count == 2)
  }

  @Test
  func relaunchRestoresDisconnectedProfilesWithoutDiagnosticsOrAutomaticProcesses() throws {
    let fixture = try ControllerFixture(
      profiles: [
        ("connected-before-relaunch", 7_080),
        ("failed-before-relaunch", 7_081),
      ]
    )
    defer { fixture.cleanup() }
    let connected = fixture.profiles[0]
    let failed = fixture.profiles[1]

    fixture.controller.connect(profileID: connected.id)
    fixture.readinessMonitor.send(.ready, observation: 0)
    fixture.processFactory.processes[0].emitStderr("connected diagnostic")
    fixture.controller.connect(profileID: failed.id)
    fixture.processFactory.processes[1].emitStderr("failed diagnostic\n")
    fixture.processFactory.processes[1].emitTermination(status: 42)

    #expect(fixture.controller.session(for: connected.id)?.status == .connected)
    #expect(fixture.controller.session(for: connected.id)?.diagnostic.isEmpty == false)
    #expect(
      fixture.controller.session(for: failed.id)?.status == .failed("failed diagnostic")
    )
    #expect(fixture.controller.session(for: failed.id)?.diagnostic.isEmpty == false)

    let freshProcessFactory = FakeTunnelProcessFactory()
    let freshPortProbe = FakeLocalPortProbe()
    let freshReadinessMonitor = FakeReadinessMonitor()
    let freshScheduler = FakeTunnelScheduler()
    let relaunchedController = TunnelController(
      store: TunnelProfileStore(defaults: fixture.defaults),
      processFactory: freshProcessFactory,
      portProbe: freshPortProbe,
      readinessMonitor: freshReadinessMonitor,
      scheduler: freshScheduler
    )

    #expect(relaunchedController.profiles == fixture.profiles)
    for profile in relaunchedController.profiles {
      let session = try #require(relaunchedController.session(for: profile.id))
      #expect(session.status == .disconnected)
      #expect(session.diagnostic.isEmpty)
      #expect(!session.isActive)
    }
    #expect(freshProcessFactory.processes.isEmpty)
    #expect(freshReadinessMonitor.observations.isEmpty)
    #expect(freshScheduler.actions.isEmpty)
  }
}

@MainActor
private final class ControllerFixture {
  let suiteName: String
  let defaults: UserDefaults
  let processFactory = FakeTunnelProcessFactory()
  let portProbe = FakeLocalPortProbe()
  let readinessMonitor = FakeReadinessMonitor()
  let scheduler = FakeTunnelScheduler()
  let controller: TunnelController
  let profiles: [TunnelProfile]

  init(profiles specifications: [(host: String, port: Int)]) throws {
    suiteName = "TunnelControllerTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(true, forKey: TunnelProfileStore.migrationCompleteKey)

    let store = TunnelProfileStore(defaults: defaults)
    var profiles: [TunnelProfile] = []
    for specification in specifications {
      profiles.append(
        try store.addProfile(
          host: specification.host,
          account: "",
          localPort: specification.port
        )
      )
    }
    self.profiles = profiles
    controller = TunnelController(
      store: store,
      processFactory: processFactory,
      portProbe: portProbe,
      readinessMonitor: readinessMonitor,
      scheduler: scheduler
    )
  }

  func cleanup() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private final class FakeLocalPortProbe: LocalPortProbing, @unchecked Sendable {
  private let lock = NSLock()
  private var unavailablePorts = Set<Int>()

  func setUnavailable(_ ports: Set<Int>) {
    lock.withLock {
      unavailablePorts = ports
    }
  }

  func isAvailable(_ port: Int) -> Bool {
    lock.withLock {
      !unavailablePorts.contains(port)
    }
  }

  func canConnect(_ port: Int) -> Bool {
    false
  }
}

@MainActor
private final class FakeTunnelProcessFactory: TunnelProcessFactory, @unchecked Sendable {
  private(set) var processes: [FakeTunnelProcess] = []

  func makeProcess() -> TunnelProcessHandle {
    let process = FakeTunnelProcess()
    processes.append(process)
    return process
  }
}

private final class FakeTunnelProcess: TunnelProcessHandle, @unchecked Sendable {
  nonisolated(unsafe) private(set) var isRunning = false

  @MainActor private(set) var executableURL: URL?
  @MainActor private(set) var arguments: [String] = []
  @MainActor private(set) var terminateCallCount = 0
  @MainActor private(set) var forceTerminateCallCount = 0
  @MainActor private(set) var invalidateCallCount = 0
  @MainActor private var stderrHandlers: [@MainActor (String) -> Void] = []
  @MainActor private var terminationHandlers: [@MainActor (Int32) -> Void] = []

  @MainActor
  func run(
    executableURL: URL,
    arguments: [String],
    stderrHandler: @escaping @MainActor (String) -> Void,
    terminationHandler: @escaping @MainActor (Int32) -> Void
  ) throws {
    self.executableURL = executableURL
    self.arguments = arguments
    stderrHandlers.append(stderrHandler)
    terminationHandlers.append(terminationHandler)
    isRunning = true
  }

  @MainActor
  func terminate() {
    terminateCallCount += 1
  }

  @MainActor
  func forceTerminate() {
    forceTerminateCallCount += 1
  }

  @MainActor
  func invalidateCallbacks() {
    invalidateCallCount += 1
  }

  @MainActor
  func emitStderr(_ text: String, launch: Int = 0) {
    stderrHandlers[launch](text)
  }

  @MainActor
  func emitTermination(status: Int32, launch: Int = 0) {
    isRunning = false
    terminationHandlers[launch](status)
  }
}

@MainActor
private final class FakeReadinessMonitor: TunnelReadinessMonitoring, @unchecked Sendable {
  struct Observation {
    let process: TunnelProcessHandle
    let port: Int
    let completion: @MainActor (TunnelReadinessResult) -> Void
    let cancellation: FakeCancellation
  }

  private(set) var observations: [Observation] = []

  func monitor(
    process: TunnelProcessHandle,
    port: Int,
    completion: @escaping @MainActor (TunnelReadinessResult) -> Void
  ) -> TunnelCancellation {
    let cancellation = FakeCancellation()
    observations.append(
      Observation(
        process: process,
        port: port,
        completion: completion,
        cancellation: cancellation
      )
    )
    return cancellation
  }

  func send(_ result: TunnelReadinessResult, observation index: Int) {
    observations[index].completion(result)
  }
}

@MainActor
private final class FakeTunnelScheduler: TunnelScheduling, @unchecked Sendable {
  struct ScheduledAction {
    let delay: TimeInterval
    let action: @MainActor () -> Void
    let cancellation: FakeCancellation
  }

  private(set) var actions: [ScheduledAction] = []

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> TunnelCancellation {
    let cancellation = FakeCancellation()
    actions.append(
      ScheduledAction(delay: delay, action: action, cancellation: cancellation)
    )
    return cancellation
  }

  func run(action index: Int) {
    let scheduledAction = actions[index]
    guard !scheduledAction.cancellation.isCancelled else {
      return
    }
    scheduledAction.action()
  }
}

private final class FakeCancellation: TunnelCancellation, @unchecked Sendable {
  nonisolated(unsafe) private(set) var isCancelled = false

  func cancel() {
    isCancelled = true
  }
}
