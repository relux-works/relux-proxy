import Foundation
import Testing

@testable import ReluxProxy

@Suite
struct TunnelProfileStoreTests {
  private static let suiteNameKey = "TunnelProfileStoreTests.suiteName"

  @Test
  func cleanInstallMigratesCurrentDefaultsIntoOneProfile() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }

    let store = TunnelProfileStore(defaults: defaults)
    let profile = try #require(store.profiles.first)

    #expect(store.profiles.count == 1)
    #expect(profile.host == "relux")
    #expect(profile.account == "administrator")
    #expect(profile.localPort == 1_080)
    #expect(defaults.bool(forKey: TunnelProfileStore.migrationCompleteKey))
  }

  @Test
  func migratesValidLegacySettingsExactlyOnceWithoutChangingThem() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }

    defaults.set(" work-bastion ", forKey: TunnelProfileStore.legacyHostKey)
    defaults.set(" deploy ", forKey: TunnelProfileStore.legacyAccountKey)
    defaults.set(9_050, forKey: TunnelProfileStore.legacyPortKey)
    let migratedID = UUID(uuidString: "4CA3B171-4C88-4B84-A33C-340B9F28DFF8")!

    let firstLaunch = TunnelProfileStore(defaults: defaults, makeUUID: { migratedID })
    let profile = try #require(firstLaunch.profiles.first)

    #expect(firstLaunch.profiles.count == 1)
    #expect(profile.id == migratedID)
    #expect(profile.host == "work-bastion")
    #expect(profile.account == "deploy")
    #expect(profile.localPort == 9_050)
    #expect(
      defaults.bool(forKey: TunnelProfileStore.migrationCompleteKey)
    )
    #expect(
      defaults.string(forKey: TunnelProfileStore.legacyHostKey) == " work-bastion "
    )
    #expect(
      defaults.string(forKey: TunnelProfileStore.legacyAccountKey) == " deploy "
    )
    #expect(
      defaults.integer(forKey: TunnelProfileStore.legacyPortKey) == 9_050
    )

    let restart = TunnelProfileStore(defaults: defaults, makeUUID: UUID.init)
    #expect(restart.profiles == firstLaunch.profiles)
  }

  @Test
  func invalidLegacyInputCreatesEmptyStoreAndBoundedDiagnostic() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }

    defaults.set("bad host", forKey: TunnelProfileStore.legacyHostKey)
    defaults.set(["not": "an integer"], forKey: TunnelProfileStore.legacyPortKey)

    let store = TunnelProfileStore(defaults: defaults)

    #expect(store.profiles.isEmpty)
    #expect(store.blockingError == nil)
    #expect(store.migrationDiagnostic != nil)
    #expect((store.migrationDiagnostic?.count ?? 0) <= 4_000)
    #expect(defaults.bool(forKey: TunnelProfileStore.migrationCompleteKey))

    let data = try #require(defaults.data(forKey: TunnelProfileStore.profilesKey))
    let payload = try JSONDecoder().decode(TunnelProfilePayload.self, from: data)
    #expect(payload.schemaVersion == 1)
    #expect(payload.profiles.isEmpty)
  }

  @Test
  func booleanLegacyPortCreatesEmptyStoreAndPreservesLegacyValues() throws {
    try assertIncompatibleLegacyPort(NSNumber(value: true))
  }

  @Test
  func floatingPointLegacyPortCreatesEmptyStoreAndPreservesLegacyValues() throws {
    try assertIncompatibleLegacyPort(NSNumber(value: 1_080.0))
  }

  @Test
  func deletedProfilesAreNotResurrectedFromLegacyKeys() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }

    defaults.set("legacy-host", forKey: TunnelProfileStore.legacyHostKey)
    let store = TunnelProfileStore(defaults: defaults)
    let migratedProfile = try #require(store.profiles.first)

    try store.removeProfile(id: migratedProfile.id)
    #expect(store.profiles.isEmpty)
    #expect(defaults.string(forKey: TunnelProfileStore.legacyHostKey) == "legacy-host")

    let restart = TunnelProfileStore(defaults: defaults)
    #expect(restart.profiles.isEmpty)
  }

  @Test
  func markerWithoutPayloadInitializesEmptyStoreWithoutReadingLegacyValues() {
    let defaults = makeDefaults()
    defer { clear(defaults) }

    defaults.set(true, forKey: TunnelProfileStore.migrationCompleteKey)
    defaults.set("must-not-return", forKey: TunnelProfileStore.legacyHostKey)

    let store = TunnelProfileStore(defaults: defaults)

    #expect(store.profiles.isEmpty)
    #expect(defaults.data(forKey: TunnelProfileStore.profilesKey) != nil)
  }

  @Test
  func validPayloadWithoutMarkerCompletesMigrationWithoutDuplicatingProfile() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }
    let profile = TunnelProfile(
      id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
      host: "existing",
      account: "",
      localPort: 7_080
    )
    let data = try JSONEncoder().encode(TunnelProfilePayload(profiles: [profile]))
    defaults.set(data, forKey: TunnelProfileStore.profilesKey)
    var generatedAnotherID = false

    let store = TunnelProfileStore(
      defaults: defaults,
      makeUUID: {
        generatedAnotherID = true
        return UUID()
      }
    )

    #expect(store.profiles == [profile])
    #expect(!generatedAnotherID)
    #expect(defaults.bool(forKey: TunnelProfileStore.migrationCompleteKey))
  }

  @Test
  func createsEditsPersistsAndRelaunchesMultipleStableProfiles() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }
    defaults.set(true, forKey: TunnelProfileStore.migrationCompleteKey)

    let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    var generatedIDs = [firstID, secondID]
    let store = TunnelProfileStore(
      defaults: defaults,
      makeUUID: { generatedIDs.removeFirst() }
    )

    let first = try store.addProfile(host: " first ", account: "", localPort: 1_080)
    let second = try store.addProfile(host: "second", account: " ops ", localPort: 1_081)
    let edited = try store.updateProfile(
      TunnelProfile(
        id: first.id,
        host: "renamed-alias",
        account: "deploy",
        localPort: 2_080
      )
    )

    #expect(first.id == firstID)
    #expect(second.id == secondID)
    #expect(edited.id == firstID)
    #expect(store.profiles.map(\.id) == [firstID, secondID])

    let restart = TunnelProfileStore(defaults: defaults)
    #expect(restart.profiles == store.profiles)
    #expect(restart.profiles[0].host == "renamed-alias")
    #expect(restart.profiles[0].localPort == 2_080)
  }

  @Test
  func duplicateOrInvalidMutationLeavesPreviousPayloadUntouched() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }
    defaults.set(true, forKey: TunnelProfileStore.migrationCompleteKey)

    let store = TunnelProfileStore(defaults: defaults)
    let first = try store.addProfile(host: "one", account: "", localPort: 1_080)
    _ = try store.addProfile(host: "two", account: "", localPort: 1_081)
    let before = try #require(defaults.data(forKey: TunnelProfileStore.profilesKey))
    let beforeProfiles = store.profiles

    #expect(throws: TunnelProfileError.duplicateLocalPort(1_080)) {
      try store.addProfile(host: "three", account: "", localPort: 1_080)
    }
    #expect(throws: TunnelProfileError.duplicateLocalPort(1_081)) {
      try store.updateProfile(
        TunnelProfile(
          id: first.id,
          host: first.host,
          account: first.account,
          localPort: 1_081
        )
      )
    }
    #expect(throws: TunnelProfileError.self) {
      try store.addProfile(host: "-invalid", account: "", localPort: 1_082)
    }

    #expect(defaults.data(forKey: TunnelProfileStore.profilesKey) == before)
    #expect(store.profiles == beforeProfiles)
  }

  @Test
  func invalidOrNewerPayloadIsPreservedAndBlocksMutations() throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }

    let original = Data(
      """
      {
        "schemaVersion": 2,
        "profiles": [{
          "id": "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
          "host": "future",
          "account": "",
          "localPort": 1080
        }]
      }
      """.utf8
    )
    defaults.set(original, forKey: TunnelProfileStore.profilesKey)

    let store = TunnelProfileStore(defaults: defaults)

    #expect(store.profiles.isEmpty)
    #expect(store.blockingError != nil)
    #expect(defaults.data(forKey: TunnelProfileStore.profilesKey) == original)
    #expect(!defaults.bool(forKey: TunnelProfileStore.migrationCompleteKey))
    #expect(throws: TunnelProfileError.self) {
      try store.addProfile(host: "host", account: "", localPort: 1_080)
    }
    #expect(defaults.data(forKey: TunnelProfileStore.profilesKey) == original)
  }

  @Test
  func storedWhitespaceInHostIsPreservedAndBlocksTheStore() throws {
    try assertStoredWhitespaceIsBlocked(host: " work-bastion ", account: "")
  }

  @Test
  func storedWhitespaceInAccountIsPreservedAndBlocksTheStore() throws {
    try assertStoredWhitespaceIsBlocked(host: "work-bastion", account: " ops ")
  }

  private func assertIncompatibleLegacyPort(_ value: NSNumber) throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }

    defaults.set(" legacy-host ", forKey: TunnelProfileStore.legacyHostKey)
    defaults.set(" legacy-account ", forKey: TunnelProfileStore.legacyAccountKey)
    defaults.set(value, forKey: TunnelProfileStore.legacyPortKey)
    let storedBefore = try #require(
      defaults.object(forKey: TunnelProfileStore.legacyPortKey) as? NSNumber
    )
    let typeBefore = String(cString: storedBefore.objCType)

    let store = TunnelProfileStore(defaults: defaults)

    #expect(store.profiles.isEmpty)
    #expect(store.blockingError == nil)
    #expect(store.migrationDiagnostic != nil)
    #expect((store.migrationDiagnostic?.count ?? 0) <= 4_000)
    #expect(defaults.bool(forKey: TunnelProfileStore.migrationCompleteKey))
    #expect(
      defaults.string(forKey: TunnelProfileStore.legacyHostKey) == " legacy-host "
    )
    #expect(
      defaults.string(forKey: TunnelProfileStore.legacyAccountKey) == " legacy-account "
    )

    let storedAfter = try #require(
      defaults.object(forKey: TunnelProfileStore.legacyPortKey) as? NSNumber
    )
    #expect(String(cString: storedAfter.objCType) == typeBefore)
    #expect(storedAfter.isEqual(to: storedBefore))

    let data = try #require(defaults.data(forKey: TunnelProfileStore.profilesKey))
    let payload = try JSONDecoder().decode(TunnelProfilePayload.self, from: data)
    #expect(payload.schemaVersion == 1)
    #expect(payload.profiles.isEmpty)
  }

  private func assertStoredWhitespaceIsBlocked(host: String, account: String) throws {
    let defaults = makeDefaults()
    defer { clear(defaults) }
    let profile = TunnelProfile(
      id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
      host: host,
      account: account,
      localPort: 1_080
    )
    let original = try JSONEncoder().encode(TunnelProfilePayload(profiles: [profile]))
    defaults.set(original, forKey: TunnelProfileStore.profilesKey)

    let store = TunnelProfileStore(defaults: defaults)

    #expect(store.profiles.isEmpty)
    let blockingError = try #require(store.blockingError)
    #expect(store.migrationDiagnostic == nil)
    #expect(defaults.data(forKey: TunnelProfileStore.profilesKey) == original)
    #expect(!defaults.bool(forKey: TunnelProfileStore.migrationCompleteKey))
    #expect(
      throws: TunnelProfileError.persistenceUnavailable(blockingError)
    ) {
      try store.addProfile(host: "new-host", account: "", localPort: 1_081)
    }
    #expect(defaults.data(forKey: TunnelProfileStore.profilesKey) == original)
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "TunnelProfileStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: Self.suiteNameKey)
    return defaults
  }

  private func clear(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: Self.suiteNameKey) else {
      return
    }
    defaults.removePersistentDomain(forName: suiteName)
  }
}
