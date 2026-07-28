import Darwin
import Foundation

protocol TunnelCancellation: AnyObject, Sendable {
  func cancel()
}

protocol TunnelProcessHandle: AnyObject, Sendable {
  var isRunning: Bool { get }

  @MainActor
  func run(
    executableURL: URL,
    arguments: [String],
    stderrHandler: @escaping @MainActor (String) -> Void,
    terminationHandler: @escaping @MainActor (Int32) -> Void
  ) throws

  @MainActor
  func terminate()

  @MainActor
  func forceTerminate()

  @MainActor
  func invalidateCallbacks()
}

protocol TunnelProcessFactory: Sendable {
  @MainActor
  func makeProcess() -> TunnelProcessHandle
}

protocol LocalPortProbing: Sendable {
  func isAvailable(_ port: Int) -> Bool
  func canConnect(_ port: Int) -> Bool
}

enum TunnelReadinessResult {
  case ready
  case timedOut
}

protocol TunnelReadinessMonitoring: Sendable {
  @MainActor
  func monitor(
    process: TunnelProcessHandle,
    port: Int,
    completion: @escaping @MainActor (TunnelReadinessResult) -> Void
  ) -> TunnelCancellation
}

protocol TunnelScheduling: Sendable {
  @MainActor
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> TunnelCancellation
}

struct SystemTunnelProcessFactory: TunnelProcessFactory {
  @MainActor
  func makeProcess() -> TunnelProcessHandle {
    SystemTunnelProcess()
  }
}

final class SystemTunnelProcess: TunnelProcessHandle, @unchecked Sendable {
  private let process = Process()
  private let eventQueue = DispatchQueue(label: "works.relux.proxy.ssh-process-events")
  private var errorPipe: Pipe?

  var isRunning: Bool {
    process.isRunning
  }

  @MainActor
  func run(
    executableURL: URL,
    arguments: [String],
    stderrHandler: @escaping @MainActor (String) -> Void,
    terminationHandler: @escaping @MainActor (Int32) -> Void
  ) throws {
    let pipe = Pipe()

    process.executableURL = executableURL
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = pipe
    errorPipe = pipe

    pipe.fileHandleForReading.readabilityHandler = { [eventQueue] handle in
      let data = handle.availableData
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
        return
      }
      eventQueue.async {
        Task { @MainActor in
          stderrHandler(text)
        }
      }
    }

    process.terminationHandler = { [eventQueue, weak pipe] terminatedProcess in
      eventQueue.async {
        pipe?.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let remainingText = String(data: remainingData, encoding: .utf8)

        Task { @MainActor in
          if let remainingText, !remainingText.isEmpty {
            stderrHandler(remainingText)
          }
          terminationHandler(terminatedProcess.terminationStatus)
        }
      }
    }

    try process.run()
  }

  @MainActor
  func terminate() {
    guard process.isRunning else {
      return
    }
    process.terminate()
  }

  @MainActor
  func forceTerminate() {
    guard process.isRunning, process.processIdentifier > 0 else {
      return
    }
    kill(process.processIdentifier, SIGKILL)
  }

  @MainActor
  func invalidateCallbacks() {
    errorPipe?.fileHandleForReading.readabilityHandler = nil
    process.terminationHandler = nil
    errorPipe = nil
  }
}

struct SystemLocalPortProbe: LocalPortProbing {
  func isAvailable(_ port: Int) -> Bool {
    withSocket(for: port) { descriptor, address in
      var address = address
      return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
          Darwin.bind(
            descriptor,
            socketAddress,
            socklen_t(MemoryLayout<sockaddr_in>.size)
          ) == 0
        }
      }
    }
  }

  func canConnect(_ port: Int) -> Bool {
    withSocket(for: port) { descriptor, address in
      var address = address
      return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
          Darwin.connect(
            descriptor,
            socketAddress,
            socklen_t(MemoryLayout<sockaddr_in>.size)
          ) == 0
        }
      }
    }
  }

  private func withSocket(
    for port: Int,
    operation: (Int32, sockaddr_in) -> Bool
  ) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      return false
    }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port).bigEndian)
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    return operation(descriptor, address)
  }
}

final class PollingTunnelReadinessMonitor: TunnelReadinessMonitoring, @unchecked Sendable {
  private let portProbe: LocalPortProbing
  private let attempts: Int
  private let interval: TimeInterval
  private let queue: DispatchQueue

  init(
    portProbe: LocalPortProbing,
    attempts: Int = 100,
    interval: TimeInterval = 0.2,
    queue: DispatchQueue = .global(qos: .utility)
  ) {
    self.portProbe = portProbe
    self.attempts = attempts
    self.interval = interval
    self.queue = queue
  }

  @MainActor
  func monitor(
    process: TunnelProcessHandle,
    port: Int,
    completion: @escaping @MainActor (TunnelReadinessResult) -> Void
  ) -> TunnelCancellation {
    let cancellation = LockedTunnelCancellation()

    queue.async { [attempts, interval, portProbe] in
      for _ in 0..<attempts {
        guard !cancellation.isCancelled else {
          return
        }
        Thread.sleep(forTimeInterval: interval)
        guard !cancellation.isCancelled, process.isRunning else {
          return
        }
        if portProbe.canConnect(port) {
          Task { @MainActor in
            guard !cancellation.isCancelled else {
              return
            }
            completion(.ready)
          }
          return
        }
      }

      guard !cancellation.isCancelled, process.isRunning else {
        return
      }
      Task { @MainActor in
        guard !cancellation.isCancelled else {
          return
        }
        completion(.timedOut)
      }
    }

    return cancellation
  }
}

struct DispatchTunnelScheduler: TunnelScheduling {
  private let queue: DispatchQueue

  init(queue: DispatchQueue = .global(qos: .utility)) {
    self.queue = queue
  }

  @MainActor
  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> TunnelCancellation {
    let workItem = DispatchWorkItem {
      Task { @MainActor in
        action()
      }
    }
    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    return WorkItemTunnelCancellation(workItem: workItem)
  }
}

private final class LockedTunnelCancellation: TunnelCancellation, @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.withLock { cancelled }
  }

  func cancel() {
    lock.withLock {
      cancelled = true
    }
  }
}

private final class WorkItemTunnelCancellation: TunnelCancellation, @unchecked Sendable {
  private let workItem: DispatchWorkItem

  init(workItem: DispatchWorkItem) {
    self.workItem = workItem
  }

  func cancel() {
    workItem.cancel()
  }
}
