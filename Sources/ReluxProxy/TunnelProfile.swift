import Foundation

struct TunnelProfile: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  var host: String
  var account: String
  var localPort: Int

  var configuration: TunnelConfiguration {
    TunnelConfiguration(host: host, account: account, localPort: localPort)
  }

  var displayTarget: String {
    configuration.target
  }

  func normalized() throws -> TunnelProfile {
    let configuration = TunnelConfiguration(
      host: host,
      account: account,
      localPort: localPort
    )
    if let validationError = configuration.validationError {
      throw TunnelProfileError.invalidProfile(validationError)
    }

    return TunnelProfile(
      id: id,
      host: configuration.normalizedHost,
      account: configuration.normalizedAccount,
      localPort: localPort
    )
  }
}

struct TunnelProfilePayload: Codable, Equatable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  var profiles: [TunnelProfile]

  init(profiles: [TunnelProfile]) {
    schemaVersion = Self.currentSchemaVersion
    self.profiles = profiles
  }
}

enum TunnelProfileValidator {
  static func normalize(_ profiles: [TunnelProfile]) throws -> [TunnelProfile] {
    try validateCollection(
      profiles.map { profile in
        try profile.normalized()
      }
    )
  }

  static func validateStored(_ profiles: [TunnelProfile]) throws -> [TunnelProfile] {
    for profile in profiles {
      let normalized = try profile.normalized()
      guard normalized == profile else {
        throw TunnelProfileError.invalidProfile(
          "Saved profile \(profile.id.uuidString) contains surrounding whitespace."
        )
      }
    }
    return try validateCollection(profiles)
  }

  private static func validateCollection(
    _ profiles: [TunnelProfile]
  ) throws -> [TunnelProfile] {
    var profileIDs = Set<UUID>()
    var localPorts = Set<Int>()

    for profile in profiles {
      guard profileIDs.insert(profile.id).inserted else {
        throw TunnelProfileError.duplicateProfileID(profile.id)
      }
      guard localPorts.insert(profile.localPort).inserted else {
        throw TunnelProfileError.duplicateLocalPort(profile.localPort)
      }
    }
    return profiles
  }
}

enum TunnelProfileError: LocalizedError, Equatable {
  case invalidProfile(String)
  case duplicateProfileID(UUID)
  case duplicateLocalPort(Int)
  case profileNotFound(UUID)
  case activeProfile(UUID)
  case persistenceUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .invalidProfile(let message):
      message
    case .duplicateProfileID(let id):
      "The saved profile identifier \(id.uuidString) is duplicated."
    case .duplicateLocalPort(let port):
      "Local SOCKS port \(port) is already assigned to another profile."
    case .profileNotFound:
      "The selected tunnel profile no longer exists."
    case .activeProfile:
      "Disconnect this tunnel before editing or removing its profile."
    case .persistenceUnavailable(let message):
      message
    }
  }
}
