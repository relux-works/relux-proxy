import Foundation

enum SSHCommandBuilder {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

    static func arguments(for configuration: TunnelConfiguration) throws -> [String] {
        if let error = configuration.validationError {
            throw SSHCommandError.invalidConfiguration(error)
        }

        return [
            "-N",
            "-C",
            "-D", configuration.localEndpoint,
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=15",
            "-o", "BatchMode=yes",
            "-o", "LogLevel=ERROR",
            configuration.target,
        ]
    }
}

enum SSHCommandError: LocalizedError, Equatable {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        }
    }
}
