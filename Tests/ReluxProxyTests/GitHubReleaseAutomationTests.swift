import Foundation
import Testing

@Suite
struct GitHubReleaseAutomationTests {
  @Test
  func workflowTargetsOnlyTheDedicatedRunnerAndFullXcode() throws {
    let workflow = try repositoryContents(at: ".github/workflows/release.yml")
    let actionlintConfiguration = try repositoryContents(at: ".github/actionlint.yaml")

    for requiredText in [
      #"tags: ["v0.2.0"]"#,
      "runs-on: [self-hosted, macOS, X64, relux-proxy-release]",
      "DEVELOPER_DIR: /Applications/Xcode.app/Contents/Developer",
      "scripts/github-release-preflight.sh",
      "xcodebuild -version",
      #"SIGN_IDENTITY: "Developer ID Application: Relux Works, LLC (262RZ595FP)""#,
      #"SIGN_KEYCHAIN="$RELEASE_KEYCHAIN" scripts/build-app.sh"#,
      #"REQUIRE_DEVELOPER_ID: "1""#,
      #"security find-identity -v -p codesigning "$RELEASE_KEYCHAIN""#,
      #"if: ${{ always() }}"#,
      "scripts/github-release-cleanup.sh",
    ] {
      #expect(workflow.contains(requiredText))
    }

    #expect(!workflow.contains("runs-on: macos-15"))
    #expect(!workflow.contains("tags: [\"v*\"]"))
    #expect(actionlintConfiguration.contains("- relux-proxy-release"))
    expectInOrder(
      [
        "scripts/github-release-preflight.sh",
        "security import",
        "security find-identity",
        "scripts/build-app.sh",
        "scripts/create-dmg.sh",
        "notarytool submit",
        "stapler staple",
        "Publish GitHub release",
        "Clean release credentials",
      ],
      in: workflow
    )
  }

  @Test
  func cleanupRemovesReleaseMaterialWhenKeychainDeletionFails() throws {
    let fileManager = FileManager.default
    let fixture = fileManager.temporaryDirectory
      .appendingPathComponent("relux-github-cleanup-\(UUID().uuidString)")
    let releaseTemp = fixture.appendingPathComponent("relux-release.failure")
    let fakeBin = fixture.appendingPathComponent("bin")
    let keychain = releaseTemp.appendingPathComponent("relux-release.keychain-db")
    let notaryKey = releaseTemp.appendingPathComponent("asc.p8")
    let securityMarker = fixture.appendingPathComponent("security-called")
    let fakeSecurity = fakeBin.appendingPathComponent("security")

    try fileManager.createDirectory(at: releaseTemp, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: fakeBin, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: fixture) }

    try Data("synthetic keychain material".utf8).write(to: keychain)
    try Data("synthetic notary material".utf8).write(to: notaryKey)
    try """
    #!/bin/bash
    printf 'called\n' > "$SECURITY_MARKER"
    exit 37
    """.write(to: fakeSecurity, atomically: true, encoding: .utf8)
    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: fakeSecurity.path
    )

    let result = try run(
      executable: "/bin/bash",
      arguments: ["scripts/github-release-cleanup.sh"],
      environment: [
        "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin",
        "RELEASE_KEYCHAIN": keychain.path,
        "RELEASE_TEMP": releaseTemp.path,
        "RUNNER_TEMP": fixture.path,
        "SECURITY_MARKER": securityMarker.path,
      ]
    )

    #expect(result.status == 37, "cleanup output: \(result.output)")
    #expect(result.output.contains("failed to delete release keychain"))
    #expect(fileManager.fileExists(atPath: securityMarker.path))
    #expect(!fileManager.fileExists(atPath: keychain.path))
    #expect(!fileManager.fileExists(atPath: notaryKey.path))
    #expect(!fileManager.fileExists(atPath: releaseTemp.path))
  }

  @Test
  func preflightAcceptsOnlyTheDedicatedV020ReleaseContext() throws {
    let accepted = try runPreflight()
    #expect(accepted.status == 0, "preflight output: \(accepted.output)")

    let wrongRepository = try runPreflight(overrides: [
      "GITHUB_REPOSITORY": "someone-else/relux-proxy"
    ])
    #expect(wrongRepository.status != 0)
    #expect(wrongRepository.output.contains("unexpected GitHub repository"))

    let wrongTag = try runPreflight(overrides: ["GITHUB_REF_NAME": "v0.2.1"])
    #expect(wrongTag.status != 0)
    #expect(wrongTag.output.contains("accepts only tag 'v0.2.0'"))

    let wrongRunner = try runPreflight(overrides: ["RUNNER_NAME": "relux-gramdrive"])
    #expect(wrongRunner.status != 0)
    #expect(wrongRunner.output.contains("dedicated release runner"))
  }

  @Test
  func preflightFailsClosedWithoutReleaseIdentityOrSecretsAndDoesNotEchoThem() throws {
    let missingIdentity = try runPreflight(overrides: ["SIGN_IDENTITY": ""])
    #expect(missingIdentity.status != 0)
    #expect(missingIdentity.output.contains("required release variable 'SIGN_IDENTITY'"))

    let wrongIdentity = try runPreflight(overrides: [
      "SIGN_IDENTITY": "Developer ID Application: Not Relux"
    ])
    #expect(wrongIdentity.status != 0)
    #expect(wrongIdentity.output.contains("not the Relux Works Developer ID"))

    let missingCertificate = try runPreflight(overrides: ["MACOS_CERT_P12": ""])
    #expect(missingCertificate.status != 0)
    #expect(missingCertificate.output.contains("required release variable 'MACOS_CERT_P12'"))

    for secret in Self.syntheticSecrets.values {
      #expect(!missingIdentity.output.contains(secret))
      #expect(!wrongIdentity.output.contains(secret))
      #expect(!missingCertificate.output.contains(secret))
    }
  }

  @Test
  func runbookDocumentsTheDedicatedRunnerWithoutClaimingPublication() throws {
    let runbook = try repositoryContents(at: "docs/github-release.md")
    let readme = try repositoryContents(at: "README.md")

    for requiredText in [
      "/Users/administrator/actions-runner-relux-proxy-release",
      "actions.runner.relux-works-relux-proxy.relux-proxy-release",
      "`self-hosted`, `macOS`, `X64`, `relux-proxy-release`",
      "/Applications/Xcode.app/Contents/Developer",
      "ASC_ISSUER_ID",
      "ASC_KEY_ID",
      "ASC_KEY_P8",
      "MACOS_CERT_P12",
      "does not create the `v0.2.0` tag",
      "must not be used by pull-request workflows",
    ] {
      #expect(runbook.contains(requiredText))
    }

    #expect(runbook.contains("online and idle"))
    #expect(readme.contains("[GitHub release runbook](docs/github-release.md)"))
  }

  private func runPreflight(
    overrides: [String: String] = [:]
  ) throws -> GitHubCommandResult {
    let commit = try currentCommit()
    var environment = [
      "GITHUB_EVENT_NAME": "push",
      "GITHUB_REPOSITORY": "relux-works/relux-proxy",
      "GITHUB_REF_TYPE": "tag",
      "GITHUB_REF_NAME": "v0.2.0",
      "GITHUB_SHA": commit,
      "GITHUB_RUN_NUMBER": "42",
      "RUNNER_NAME": "relux-proxy-release",
      "RUNNER_OS": "macOS",
      "RUNNER_ARCH": "X64",
      "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
      "SIGN_IDENTITY": "Developer ID Application: Relux Works, LLC (262RZ595FP)",
    ]
    environment.merge(Self.syntheticSecrets) { _, replacement in replacement }
    environment.merge(overrides) { _, replacement in replacement }

    return try run(
      executable: "/bin/bash",
      arguments: ["scripts/github-release-preflight.sh"],
      environment: environment
    )
  }

  private func currentCommit() throws -> String {
    let result = try run(
      executable: "/usr/bin/git",
      arguments: ["rev-parse", "HEAD"]
    )
    #expect(result.status == 0, "git output: \(result.output)")
    return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func expectInOrder(_ markers: [String], in contents: String) {
    var searchStart = contents.startIndex
    for marker in markers {
      let remaining = searchStart..<contents.endIndex
      let match = contents.range(of: marker, range: remaining)
      #expect(match != nil, "missing or out-of-order marker: \(marker)")
      guard let match else {
        return
      }
      searchStart = match.upperBound
    }
  }

  private func run(
    executable: String,
    arguments: [String],
    environment: [String: String] = [:]
  ) throws -> GitHubCommandResult {
    let process = Process()
    let output = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = repositoryRoot
    process.standardOutput = output
    process.standardError = output
    process.environment = ProcessInfo.processInfo.environment.merging(environment) {
      _, replacement in replacement
    }

    try process.run()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    return GitHubCommandResult(
      status: process.terminationStatus,
      output: String(decoding: data, as: UTF8.self)
    )
  }

  private func repositoryContents(at relativePath: String) throws -> String {
    try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static let syntheticSecrets = [
    "ASC_ISSUER_ID": "synthetic-issuer-do-not-log",
    "ASC_KEY_ID": "synthetic-key-id-do-not-log",
    "ASC_KEY_P8": "synthetic-private-key-do-not-log",
    "MACOS_CERT_P12": "synthetic-certificate-do-not-log",
  ]
}

private struct GitHubCommandResult {
  let status: Int32
  let output: String
}
