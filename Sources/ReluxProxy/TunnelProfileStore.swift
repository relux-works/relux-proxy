import CoreFoundation
import Foundation

final class TunnelProfileStore {
  static let profilesKey = "legacySocksProfiles.v1"
  static let migrationCompleteKey = "legacySocksProfiles.migration.v1.complete"

  static let legacyHostKey = "sshHost"
  static let legacyAccountKey = "sshAccount"
  static let legacyPortKey = "localPort"

  private static let defaultHost = "relux"
  private static let defaultAccount = "administrator"
  private static let defaultPort = 1_080
  private static let maximumDiagnosticLength = 4_000

  private let defaults: UserDefaults
  private let makeUUID: () -> UUID
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  private(set) var profiles: [TunnelProfile] = []
  private(set) var migrationDiagnostic: String?
  private(set) var blockingError: String?

  init(
    defaults: UserDefaults = .standard,
    makeUUID: @escaping () -> UUID = UUID.init
  ) {
    self.defaults = defaults
    self.makeUUID = makeUUID

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
    decoder = JSONDecoder()

    loadOrMigrate()
  }

  @discardableResult
  func addProfile(host: String, account: String, localPort: Int) throws -> TunnelProfile {
    try requireWritableStore()

    let profile = TunnelProfile(
      id: makeUUID(),
      host: host,
      account: account,
      localPort: localPort
    )
    try persist(profiles + [profile])
    return try requireProfile(id: profile.id)
  }

  @discardableResult
  func updateProfile(_ profile: TunnelProfile) throws -> TunnelProfile {
    try requireWritableStore()
    guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
      throw TunnelProfileError.profileNotFound(profile.id)
    }

    var candidate = profiles
    candidate[index] = profile
    try persist(candidate)
    return try requireProfile(id: profile.id)
  }

  func removeProfile(id: UUID) throws {
    try requireWritableStore()
    guard profiles.contains(where: { $0.id == id }) else {
      throw TunnelProfileError.profileNotFound(id)
    }

    try persist(profiles.filter { $0.id != id })
  }

  private func loadOrMigrate() {
    if let storedObject = defaults.object(forKey: Self.profilesKey) {
      guard let data = storedObject as? Data else {
        setBlockingError(
          "Saved tunnel profiles have an incompatible data type. "
            + "The existing value was preserved; reset it explicitly before continuing."
        )
        return
      }
      loadExistingPayload(data)
      return
    }

    if migrationIsComplete {
      initializeEmptyStore()
    } else {
      migrateLegacySettings()
    }
  }

  private func loadExistingPayload(_ data: Data) {
    do {
      let payload = try decoder.decode(TunnelProfilePayload.self, from: data)
      guard payload.schemaVersion == TunnelProfilePayload.currentSchemaVersion else {
        throw StoredPayloadError.unsupportedSchema(payload.schemaVersion)
      }

      profiles = try TunnelProfileValidator.validateStored(payload.profiles)
      if !migrationIsComplete {
        defaults.set(true, forKey: Self.migrationCompleteKey)
      }
    } catch {
      setBlockingError(
        "Saved tunnel profiles could not be loaded: \(error.localizedDescription) "
          + "The existing value was preserved; reset it explicitly before continuing."
      )
    }
  }

  private func initializeEmptyStore() {
    do {
      try writePayload([])
      profiles = []
    } catch {
      setBlockingError(
        "An empty tunnel profile store could not be created: \(error.localizedDescription)")
    }
  }

  private func migrateLegacySettings() {
    do {
      let profile = TunnelProfile(
        id: makeUUID(),
        host: try legacyString(forKey: Self.legacyHostKey, defaultValue: Self.defaultHost),
        account: try legacyString(
          forKey: Self.legacyAccountKey,
          defaultValue: Self.defaultAccount
        ),
        localPort: try legacyPort()
      )
      let normalizedProfiles = try TunnelProfileValidator.normalize([profile])
      try writePayload(normalizedProfiles)
      profiles = normalizedProfiles
      defaults.set(true, forKey: Self.migrationCompleteKey)
    } catch {
      do {
        try writePayload([])
        profiles = []
        migrationDiagnostic = Self.bounded(
          "Legacy tunnel settings were not migrated: \(error.localizedDescription) "
            + "Create a new profile manually."
        )
        defaults.set(true, forKey: Self.migrationCompleteKey)
      } catch {
        setBlockingError(
          "Legacy tunnel settings could not be migrated and an empty profile store "
            + "could not be created: \(error.localizedDescription)"
        )
      }
    }
  }

  private func legacyString(forKey key: String, defaultValue: String) throws -> String {
    guard let value = defaults.object(forKey: key) else {
      return defaultValue
    }
    guard let string = value as? String else {
      throw LegacyMigrationError.incompatibleType(key)
    }
    return string
  }

  private func legacyPort() throws -> Int {
    guard let value = defaults.object(forKey: Self.legacyPortKey) else {
      return Self.defaultPort
    }
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      !CFNumberIsFloatType(number)
    else {
      throw LegacyMigrationError.incompatibleType(Self.legacyPortKey)
    }

    var signedValue: Int64 = 0
    guard CFNumberGetValue(number, .sInt64Type, &signedValue),
      let port = Int(exactly: signedValue)
    else {
      throw LegacyMigrationError.incompatibleType(Self.legacyPortKey)
    }
    return port
  }

  private func persist(_ candidate: [TunnelProfile]) throws {
    let normalized = try TunnelProfileValidator.normalize(candidate)
    try writePayload(normalized)
    profiles = normalized
  }

  private func writePayload(_ profiles: [TunnelProfile]) throws {
    let data = try encoder.encode(TunnelProfilePayload(profiles: profiles))
    defaults.set(data, forKey: Self.profilesKey)
  }

  private func requireWritableStore() throws {
    if let blockingError {
      throw TunnelProfileError.persistenceUnavailable(blockingError)
    }
  }

  private func requireProfile(id: UUID) throws -> TunnelProfile {
    guard let profile = profiles.first(where: { $0.id == id }) else {
      throw TunnelProfileError.profileNotFound(id)
    }
    return profile
  }

  private var migrationIsComplete: Bool {
    (defaults.object(forKey: Self.migrationCompleteKey) as? Bool) == true
  }

  private func setBlockingError(_ message: String) {
    profiles = []
    blockingError = Self.bounded(message)
  }

  private static func bounded(_ message: String) -> String {
    guard message.count > maximumDiagnosticLength else {
      return message
    }
    return String(message.suffix(maximumDiagnosticLength))
  }
}

private enum LegacyMigrationError: LocalizedError {
  case incompatibleType(String)

  var errorDescription: String? {
    switch self {
    case .incompatibleType(let key):
      "Legacy preference \(key) has an incompatible value type."
    }
  }
}

private enum StoredPayloadError: LocalizedError {
  case unsupportedSchema(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version):
      "Schema version \(version) is not supported."
    }
  }
}
