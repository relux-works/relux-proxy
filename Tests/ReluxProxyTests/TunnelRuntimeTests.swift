import Foundation
import Testing

@testable import ReluxProxy

@MainActor
@Suite(.serialized)
struct TunnelRuntimeTests {
  @Test
  func systemProcessCapturesStderrAndTerminationWithoutAShell() async throws {
    let process = SystemTunnelProcess()
    let recorder = ProcessEventRecorder()
    let missingPath = "/tmp/relux-proxy-missing-\(UUID().uuidString)"

    try process.run(
      executableURL: URL(fileURLWithPath: "/bin/ls"),
      arguments: [missingPath],
      stderrHandler: { recorder.stderr += $0 },
      terminationHandler: { recorder.terminationStatus = $0 }
    )

    #expect(await waitUntil { recorder.terminationStatus != nil })
    #expect(recorder.terminationStatus != 0)
    #expect(recorder.stderr.contains(missingPath))
    #expect(!process.isRunning)

    process.terminate()
    process.forceTerminate()
    process.invalidateCallbacks()
  }

  @Test(arguments: [ProcessStop.terminate, ProcessStop.forceTerminate])
  func systemProcessStopsALocalChild(_ stop: ProcessStop) async throws {
    let process = SystemTunnelProcess()
    let recorder = ProcessEventRecorder()

    try process.run(
      executableURL: URL(fileURLWithPath: "/bin/sleep"),
      arguments: ["30"],
      stderrHandler: { recorder.stderr += $0 },
      terminationHandler: { recorder.terminationStatus = $0 }
    )
    #expect(process.isRunning)

    switch stop {
    case .terminate:
      process.terminate()
    case .forceTerminate:
      process.forceTerminate()
    }

    let stopped = await waitUntil { recorder.terminationStatus != nil }
    if !stopped, process.isRunning {
      process.forceTerminate()
    }

    #expect(stopped)
    #expect(recorder.terminationStatus != 0)
    #expect(!process.isRunning)
    process.invalidateCallbacks()
  }

  @Test
  func systemFactoryCreatesIndependentProcessHandles() {
    let factory = SystemTunnelProcessFactory()

    let first = factory.makeProcess()
    let second = factory.makeProcess()

    #expect(first !== second)
    #expect(!first.isRunning)
    #expect(!second.isRunning)
  }

  @Test
  func readinessMonitorReportsReadyAndTimedOutResults() async {
    let process = StubRunningProcess()

    let readyProbe = StubPortProbe(connectResults: [false, true])
    let readyMonitor = PollingTunnelReadinessMonitor(
      portProbe: readyProbe,
      attempts: 3,
      interval: 0.001,
      queue: DispatchQueue(label: "TunnelRuntimeTests.ready")
    )
    let readyRecorder = ReadinessRecorder()
    let readyCancellation = readyMonitor.monitor(process: process, port: 1_080) {
      readyRecorder.result = $0
    }

    #expect(await waitUntil { readyRecorder.result != nil })
    #expect(readyRecorder.result == .ready)
    #expect(readyProbe.observedPorts == [1_080, 1_080])
    readyCancellation.cancel()

    let timeoutProbe = StubPortProbe(connectResults: [false, false])
    let timeoutMonitor = PollingTunnelReadinessMonitor(
      portProbe: timeoutProbe,
      attempts: 2,
      interval: 0.001,
      queue: DispatchQueue(label: "TunnelRuntimeTests.timeout")
    )
    let timeoutRecorder = ReadinessRecorder()
    let timeoutCancellation = timeoutMonitor.monitor(process: process, port: 1_081) {
      timeoutRecorder.result = $0
    }

    #expect(await waitUntil { timeoutRecorder.result != nil })
    #expect(timeoutRecorder.result == .timedOut)
    #expect(timeoutProbe.observedPorts == [1_081, 1_081])
    timeoutCancellation.cancel()
  }

  @Test
  func readinessMonitorCancellationAndStoppedProcessSuppressCallbacks() async throws {
    let runningProcess = StubRunningProcess()
    let cancelledProbe = StubPortProbe(connectResults: [true])
    let cancelledMonitor = PollingTunnelReadinessMonitor(
      portProbe: cancelledProbe,
      attempts: 1,
      interval: 0.02,
      queue: DispatchQueue(label: "TunnelRuntimeTests.cancelled")
    )
    let cancelledRecorder = ReadinessRecorder()
    let cancellation = cancelledMonitor.monitor(process: runningProcess, port: 1_082) {
      cancelledRecorder.result = $0
    }
    cancellation.cancel()

    try await Task.sleep(for: .milliseconds(50))
    #expect(cancelledRecorder.result == nil)
    #expect(cancelledProbe.observedPorts.isEmpty)

    let stoppedProcess = StubRunningProcess(isRunning: false)
    let stoppedProbe = StubPortProbe(connectResults: [true])
    let stoppedMonitor = PollingTunnelReadinessMonitor(
      portProbe: stoppedProbe,
      attempts: 1,
      interval: 0.001,
      queue: DispatchQueue(label: "TunnelRuntimeTests.stopped")
    )
    let stoppedRecorder = ReadinessRecorder()
    _ = stoppedMonitor.monitor(process: stoppedProcess, port: 1_083) {
      stoppedRecorder.result = $0
    }

    try await Task.sleep(for: .milliseconds(20))
    #expect(stoppedRecorder.result == nil)
    #expect(stoppedProbe.observedPorts.isEmpty)
  }

  @Test
  func dispatchSchedulerRunsAndCancelsActions() async throws {
    let scheduler = DispatchTunnelScheduler(
      queue: DispatchQueue(label: "TunnelRuntimeTests.scheduler")
    )
    let recorder = ScheduledActionRecorder()
    let completed = scheduler.schedule(after: 0.001) {
      recorder.completedActionCount += 1
    }

    #expect(await waitUntil { recorder.completedActionCount == 1 })
    completed.cancel()

    let cancelled = scheduler.schedule(after: 0.02) {
      recorder.completedActionCount += 1
    }
    cancelled.cancel()
    try await Task.sleep(for: .milliseconds(50))

    #expect(recorder.completedActionCount == 1)
  }

  private func waitUntil(
    attempts: Int = 200,
    condition: @escaping @MainActor () -> Bool
  ) async -> Bool {
    for _ in 0..<attempts {
      if condition() {
        return true
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
  }
}

enum ProcessStop: CaseIterable, CustomTestStringConvertible, Sendable {
  case terminate
  case forceTerminate

  var testDescription: String {
    switch self {
    case .terminate: "terminate"
    case .forceTerminate: "force terminate"
    }
  }
}

@MainActor
private final class ProcessEventRecorder {
  var stderr = ""
  var terminationStatus: Int32?
}

@MainActor
private final class ReadinessRecorder {
  var result: TunnelReadinessResult?
}

@MainActor
private final class ScheduledActionRecorder {
  var completedActionCount = 0
}

private final class StubRunningProcess: TunnelProcessHandle, @unchecked Sendable {
  nonisolated(unsafe) var isRunning: Bool

  init(isRunning: Bool = true) {
    self.isRunning = isRunning
  }

  @MainActor
  func run(
    executableURL: URL,
    arguments: [String],
    stderrHandler: @escaping @MainActor (String) -> Void,
    terminationHandler: @escaping @MainActor (Int32) -> Void
  ) throws {}

  @MainActor
  func terminate() {}

  @MainActor
  func forceTerminate() {}

  @MainActor
  func invalidateCallbacks() {}
}

private final class StubPortProbe: LocalPortProbing, @unchecked Sendable {
  private let lock = NSLock()
  private var connectResults: [Bool]
  private var ports: [Int] = []

  init(connectResults: [Bool]) {
    self.connectResults = connectResults
  }

  var observedPorts: [Int] {
    lock.withLock { ports }
  }

  func isAvailable(_ port: Int) -> Bool {
    true
  }

  func canConnect(_ port: Int) -> Bool {
    lock.withLock {
      ports.append(port)
      guard !connectResults.isEmpty else {
        return false
      }
      return connectResults.removeFirst()
    }
  }
}
