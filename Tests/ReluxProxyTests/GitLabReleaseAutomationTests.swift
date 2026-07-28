import Foundation
import Testing

@Suite
struct GitLabReleaseAutomationTests {
  @Test
  func pipelineUsesTrustedMacOSReleaseGatesAndExactAssets() throws {
    let pipeline = try repositoryContents(at: ".gitlab-ci.yml")

    for requiredText in [
      "release_v0_2_0:",
      "verify_v0_2_0:",
      "relux-release",
      "resource_group: relux-production-release",
      "environment:",
      "name: production",
      "scripts/release-macos.sh",
      "scripts/upload-gitlab-release-assets.sh",
      "scripts/verify-gitlab-release.sh",
      "ReluxProxy-v0.2.0-universal.dmg",
      "ReluxProxy.dmg",
      "SHA256SUMS",
      "RELUX_GITLAB_PROJECT_ID",
      "description: \"./release-notes/v0.2.0.md\"",
    ] {
      #expect(pipeline.contains(requiredText))
    }
  }

  @Test
  func productionScriptsFailClosedAcrossSigningAndPublication() throws {
    let preflight = try repositoryContents(at: "scripts/gitlab-release-preflight.sh")
    let release = try repositoryContents(at: "scripts/release-macos.sh")
    let upload = try repositoryContents(at: "scripts/upload-gitlab-release-assets.sh")
    let verify = try repositoryContents(at: "scripts/verify-gitlab-release.sh")
    let appBuild = try repositoryContents(at: "scripts/build-app.sh")

    for requiredText in [
      "gitlab.wildberries.ru",
      "RELUX_GITLAB_HOST",
      "RELUX_GITLAB_PROJECT_PATH",
      "RELUX_GITLAB_PROJECT_ID",
      "RELUX_ACCEPTED_RELEASE_SHA",
      "CI_COMMIT_REF_PROTECTED",
      "CI_RUNNER_TAGS",
    ] {
      #expect(preflight.contains(requiredText))
    }

    for requiredText in [
      "REQUIRE_DEVELOPER_ID=1",
      #"lipo "$BINARY" -verify_arch arm64 x86_64"#,
      "notarytool submit",
      "notary_status",
      "stapler staple",
      "stapler validate",
      "spctl -a",
      "shasum -a 256 -c SHA256SUMS",
    ] {
      #expect(release.contains(requiredText))
    }
    expectInOrder(
      [
        "codesign --verify --deep --strict",
        "notarytool submit",
        #"[[ "$notary_status" == "Accepted" ]]"#,
        "notarytool log",
        "stapler staple",
        "stapler validate",
        #"codesign --verify --strict"#,
        "spctl -a",
        #"cmp -s "$VERSIONED_DMG" "$DIST/ReluxProxy.dmg""#,
        "shasum -a 256 -c SHA256SUMS",
      ],
      in: release
    )
    #expect(release.contains("gitlab_project_id=$CI_PROJECT_ID"))

    #expect(upload.contains(#"--header "JOB-TOKEN: $CI_JOB_TOKEN""#))
    #expect(upload.contains(#"--upload-file "$DIST/$asset""#))
    #expect(upload.contains("--max-redirs 0"))
    #expect(upload.contains(#""201""#))
    #expect(!upload.contains("--location"))
    #expect(
      verify.contains(
        #"DIRECT_DOWNLOAD_BASE="$CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG/downloads""#
      )
    )
    #expect(!verify.contains("/-/releases/"))
    #expect(verify.contains("--max-redirs 0"))
    #expect(verify.contains("is_gitlab_origin"))
    #expect(!verify.contains("--location"))
    #expect(verify.contains("published_commit"))
    #expect(verify.contains("shasum -a 256 -c SHA256SUMS"))
    #expect(appBuild.contains("an ad-hoc signature is forbidden for a production release"))
    #expect(appBuild.contains("required signing identity"))
  }

  @Test
  func preflightAcceptsOnlyMatchingProtectedReleaseContext() throws {
    let commit = try currentCommit()
    let accepted = try runPreflight(
      commit: commit,
      host: "gitlab.relux.example",
      expectedHost: "gitlab.relux.example"
    )

    #expect(accepted.status == 0, "preflight output: \(accepted.output)")

    let excluded = try runPreflight(
      commit: commit,
      host: "gitlab.wildberries.ru",
      expectedHost: "gitlab.wildberries.ru"
    )

    #expect(excluded.status != 0)
    #expect(excluded.output.contains("explicitly excluded"))

    let wrongCommit = try runPreflight(
      commit: commit,
      acceptedCommit: String(repeating: "0", count: 40),
      host: "gitlab.relux.example",
      expectedHost: "gitlab.relux.example"
    )

    #expect(wrongCommit.status != 0)
    #expect(wrongCommit.output.contains("accepted release commit"))

    let wrongProjectID = try runPreflight(
      commit: commit,
      host: "gitlab.relux.example",
      expectedHost: "gitlab.relux.example",
      expectedProjectID: "43"
    )

    #expect(wrongProjectID.status != 0)
    #expect(wrongProjectID.output.contains("confirmed Relux GitLab project ID"))

    let missingProjectID = try runPreflight(
      commit: commit,
      host: "gitlab.relux.example",
      expectedHost: "gitlab.relux.example",
      expectedProjectID: nil
    )

    #expect(missingProjectID.status != 0)
    #expect(missingProjectID.output.contains("RELUX_GITLAB_PROJECT_ID"))
  }

  @Test
  func productionBuildRejectsAdHocSignatureBeforeBuilding() throws {
    let result = try run(
      executable: "/bin/bash",
      arguments: ["scripts/build-app.sh"],
      environment: [
        "SIGN_IDENTITY": "-",
        "REQUIRE_DEVELOPER_ID": "1",
      ]
    )

    #expect(result.status != 0)
    #expect(result.output.contains("ad-hoc signature is forbidden"))
  }

  @Test
  func releaseDocumentationDoesNotClaimAnUnpublishedGitLabRelease() throws {
    let contract = try repositoryContents(at: ".spec/legacy-socks-multi-tunnel.md")
    let currentState = try repositoryContents(at: "docs/current-state.md")
    let runbook = try repositoryContents(at: "docs/gitlab-release.md")
    let notes = try repositoryContents(at: "release-notes/v0.2.0.md")

    #expect(contract.contains("shipped product behavior in Relux Proxy v0.2.0"))
    #expect(contract.contains("no GitLab release is claimed"))
    #expect(currentState.contains("no GitLab v0.2.0 release is currently claimed"))
    #expect(runbook.contains("Current external blocker"))
    #expect(runbook.contains("Masked and hidden"))
    #expect(runbook.contains("RELUX_GITLAB_PROJECT_ID"))
    #expect(
      runbook.contains(
        "CI_API_V4_URL/projects/$CI_PROJECT_ID/releases/$CI_COMMIT_TAG/downloads/<asset>"
      )
    )
    #expect(notes.contains("SSH config alias"))
    #expect(notes.contains("concurrent local SOCKS endpoints"))
  }

  private func runPreflight(
    commit: String,
    acceptedCommit: String? = nil,
    host: String,
    expectedHost: String,
    expectedProjectID: String? = "42"
  ) throws -> CommandResult {
    let projectPath = "relux/relux-proxy"
    var environment = [
      "CI_SERVER_HOST": host,
      "CI_SERVER_URL": "https://\(host)",
      "CI_PROJECT_PATH": projectPath,
      "CI_PROJECT_ID": "42",
      "CI_PROJECT_URL": "https://\(host)/\(projectPath)",
      "CI_API_V4_URL": "https://\(host)/api/v4",
      "CI_COMMIT_TAG": "v0.2.0",
      "CI_COMMIT_SHA": commit,
      "CI_COMMIT_REF_PROTECTED": "true",
      "CI_PIPELINE_SOURCE": "push",
      "CI_RUNNER_TAGS": #"["macos", "relux-release"]"#,
      "RELUX_GITLAB_HOST": expectedHost,
      "RELUX_GITLAB_PROJECT_PATH": projectPath,
      "RELUX_ACCEPTED_RELEASE_SHA": acceptedCommit ?? commit,
    ]
    if let expectedProjectID {
      environment["RELUX_GITLAB_PROJECT_ID"] = expectedProjectID
    }

    return try run(
      executable: "/bin/bash",
      arguments: ["scripts/gitlab-release-preflight.sh"],
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
  ) throws -> CommandResult {
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
    return CommandResult(
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
}

private struct CommandResult {
  let status: Int32
  let output: String
}
