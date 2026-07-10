import Combine
import Darwin
import Foundation

enum TunnelStatus: Equatable {
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

    var preventsEditing: Bool {
        switch self {
        case .connecting, .connected, .disconnecting: true
        case .disconnected, .failed: false
        }
    }

    var isConnected: Bool {
        self == .connected
    }
}

final class TunnelController: ObservableObject {
    static let shared = TunnelController()

    @Published private(set) var status: TunnelStatus = .disconnected
    @Published private(set) var diagnostic = ""

    private var process: Process?
    private var errorPipe: Pipe?
    private var requestedStop = false

    private init() {}

    func connect(configuration: TunnelConfiguration) {
        guard process == nil else { return }

        do {
            let arguments = try SSHCommandBuilder.arguments(for: configuration)
            guard Self.isLocalPortAvailable(configuration.localPort) else {
                throw TunnelLaunchError.localPortInUse(configuration.localEndpoint)
            }
            let process = Process()
            let pipe = Pipe()

            process.executableURL = SSHCommandBuilder.executableURL
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    return
                }
                DispatchQueue.main.async {
                    self?.appendDiagnostic(text)
                }
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                DispatchQueue.main.async {
                    self?.handleTermination(of: terminatedProcess)
                }
            }

            requestedStop = false
            diagnostic = ""
            status = .connecting
            self.process = process
            errorPipe = pipe

            try process.run()
            monitorReadiness(of: process, port: configuration.localPort)
        } catch {
            clearProcess()
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            diagnostic = message
            status = .failed(message)
        }
    }

    func disconnect() {
        guard let process else {
            status = .disconnected
            return
        }

        requestedStop = true
        status = .disconnecting
        process.terminate()

        let processIdentifier = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                kill(processIdentifier, SIGKILL)
            }
        }
    }

    func shutdown() {
        guard let process else { return }
        requestedStop = true
        kill(process.processIdentifier, SIGTERM)
    }

    private func monitorReadiness(of monitoredProcess: Process, port: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for _ in 0..<100 {
                usleep(200_000)
                guard monitoredProcess.isRunning else { return }

                if Self.canConnect(toLocalPort: port) {
                    DispatchQueue.main.async {
                        guard let self, self.process === monitoredProcess else { return }
                        self.status = .connected
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                guard let self, self.process === monitoredProcess else { return }
                self.appendDiagnostic("Timed out waiting for the local SOCKS port to open.")
                monitoredProcess.terminate()
            }
        }
    }

    private static func canConnect(toLocalPort port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

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

    private static func isLocalPortAvailable(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

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

    private func appendDiagnostic(_ text: String) {
        diagnostic += text
        if diagnostic.count > 4_000 {
            diagnostic = String(diagnostic.suffix(4_000))
        }
    }

    private func handleTermination(of terminatedProcess: Process) {
        guard process === terminatedProcess else { return }

        let stoppedByUser = requestedStop
        let exitCode = terminatedProcess.terminationStatus
        let message = diagnostic
            .split(whereSeparator: \Character.isNewline)
            .last
            .map(String.init)
            ?? "SSH exited with status \(exitCode)."

        clearProcess()
        if stoppedByUser {
            diagnostic = ""
            status = .disconnected
        } else {
            diagnostic = message
            status = .failed(message)
        }
    }

    private func clearProcess() {
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe = nil
        process = nil
        requestedStop = false
    }
}

private enum TunnelLaunchError: LocalizedError {
    case localPortInUse(String)

    var errorDescription: String? {
        switch self {
        case let .localPortInUse(endpoint):
            return "Local port \(endpoint) is already in use. Stop the existing tunnel or choose another port."
        }
    }
}
