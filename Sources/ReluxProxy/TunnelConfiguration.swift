import Foundation

struct TunnelConfiguration: Equatable {
  let host: String
  let account: String
  let localPort: Int

  var normalizedHost: String {
    host.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var normalizedAccount: String {
    account.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var target: String {
    normalizedAccount.isEmpty
      ? normalizedHost
      : "\(normalizedAccount)@\(normalizedHost)"
  }

  var sshDestination: String {
    normalizedHost
  }

  var localEndpoint: String {
    "127.0.0.1:\(localPort)"
  }

  var validationError: String? {
    if normalizedHost.isEmpty {
      return "Enter an SSH host or an alias from ~/.ssh/config."
    }
    if normalizedHost.contains(where: \Character.isWhitespace) {
      return "The SSH host cannot contain whitespace."
    }
    if normalizedHost.hasPrefix("-") {
      return "The SSH host cannot begin with -."
    }
    if normalizedAccount.contains(where: \Character.isWhitespace)
      || normalizedAccount.contains("@")
    {
      return "The SSH account must not contain whitespace or @."
    }
    if !(1...65_535).contains(localPort) {
      return "The local port must be between 1 and 65535."
    }
    return nil
  }
}
