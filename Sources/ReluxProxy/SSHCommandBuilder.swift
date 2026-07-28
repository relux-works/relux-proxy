import Foundation

enum SSHCommandBuilder {
  static let executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

  static func arguments(for configuration: TunnelConfiguration) throws -> [String] {
    if let error = configuration.validationError {
      throw SSHCommandError.invalidConfiguration(error)
    }

    var arguments = [
      "-N",
      "-C",
      "-D", configuration.localEndpoint,
      "-o", "ExitOnForwardFailure=yes",
      "-o", "ServerAliveInterval=30",
      "-o", "ServerAliveCountMax=3",
      "-o", "ConnectTimeout=15",
      "-o", "BatchMode=yes",
      "-o", "LogLevel=ERROR",
    ]
    if !configuration.normalizedAccount.isEmpty {
      arguments.append(contentsOf: ["-l", configuration.normalizedAccount])
    }
    arguments.append(configuration.sshDestination)
    return arguments
  }
}

enum SSHCommandError: LocalizedError, Equatable {
  case invalidConfiguration(String)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message):
      return message
    }
  }
}
