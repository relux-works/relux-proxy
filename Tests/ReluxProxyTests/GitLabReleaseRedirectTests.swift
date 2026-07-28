import Foundation
import Testing

@Suite(.serialized)
struct GitLabReleaseRedirectTests {
  @Test
  func verifierKeepsAuthenticationOnGitLabAndDropsItBeforeExternalRedirect() throws {
    let execution = try runVerificationScenario("positive")

    #expect(execution.result.status == 0, "verifier output: \(execution.result.output)")
    #expect(execution.gitLabRequests.contains(#""path": "/same-origin/"#))
    #expect(!execution.gitLabRequests.contains(#""authenticated": false"#))

    let externalRequests = execution.externalRequests.split(separator: "\n")
    #expect(externalRequests.count == 2)
    #expect(!execution.externalRequests.contains(#""job_token_present": true"#))
    #expect(!execution.externalRequests.contains(Self.syntheticToken))
  }

  @Test(
    arguments: [
      "unsafe-http",
      "missing-location",
      "malformed-location",
      "excessive-redirects",
      "unexpected-status",
      "wrong-metadata",
    ]
  )
  func verifierFailsClosedForUnsafeRedirectOrMetadata(_ scenario: String) throws {
    let execution = try runVerificationScenario(scenario)

    #expect(execution.result.status != 0, "scenario \(scenario) unexpectedly passed")
    #expect(
      execution.result.output.contains(expectedFailureText(for: scenario)),
      "scenario \(scenario) output: \(execution.result.output)"
    )
    #expect(!execution.externalRequests.contains(#""job_token_present": true"#))
    #expect(!execution.externalRequests.contains(Self.syntheticToken))
  }

  private func expectedFailureText(for scenario: String) -> String {
    switch scenario {
    case "unsafe-http":
      "redirect URL must use HTTPS"
    case "missing-location":
      "exactly one non-empty Location header"
    case "malformed-location":
      "absolute HTTPS URL or absolute path"
    case "excessive-redirects":
      "exceeded 5 redirects"
    case "unexpected-status":
      "unexpected HTTP status '418'"
    case "wrong-metadata":
      "does not target the confirmed project package"
    default:
      "error:"
    }
  }

  private func runVerificationScenario(_ scenario: String) throws -> RedirectExecution {
    let fileManager = FileManager.default
    let fixture = fileManager.temporaryDirectory
      .appendingPathComponent("relux-release-redirect-\(UUID().uuidString)")
    try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: fixture) }

    let scripts = fixture.appendingPathComponent("scripts")
    let dist = fixture.appendingPathComponent("dist")
    try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: dist, withIntermediateDirectories: true)

    let verifier = scripts.appendingPathComponent("verify-gitlab-release.sh")
    try fileManager.copyItem(
      at: repositoryRoot.appendingPathComponent("scripts/verify-gitlab-release.sh"),
      to: verifier
    )
    try makeExecutable(verifier)

    let preflight = scripts.appendingPathComponent("gitlab-release-preflight.sh")
    try "#!/bin/bash\nset -euo pipefail\n".write(
      to: preflight,
      atomically: true,
      encoding: .utf8
    )
    try makeExecutable(preflight)

    let versionedName = "ReluxProxy-v0.2.0-universal.dmg"
    let stableName = "ReluxProxy.dmg"
    let payload = Data("synthetic notarized DMG bytes\n".utf8)
    try payload.write(to: dist.appendingPathComponent(versionedName))
    try payload.write(to: dist.appendingPathComponent(stableName))

    let checksum = try runRedirectCommand(
      executable: "/usr/bin/shasum",
      arguments: ["-a", "256", versionedName, stableName],
      currentDirectory: dist
    )
    guard checksum.status == 0 else {
      throw RedirectFixtureError.setup("shasum failed: \(checksum.output)")
    }
    try checksum.output.write(
      to: dist.appendingPathComponent("SHA256SUMS"),
      atomically: true,
      encoding: .utf8
    )

    let opensslConfiguration = fixture.appendingPathComponent("openssl.cnf")
    try Self.opensslConfiguration.write(
      to: opensslConfiguration,
      atomically: true,
      encoding: .utf8
    )
    let certificate = fixture.appendingPathComponent("certificate.pem")
    let privateKey = fixture.appendingPathComponent("private-key.pem")
    let certificateResult = try runRedirectCommand(
      executable: "/usr/bin/openssl",
      arguments: [
        "req",
        "-x509",
        "-nodes",
        "-newkey",
        "rsa:2048",
        "-keyout",
        privateKey.path,
        "-out",
        certificate.path,
        "-days",
        "1",
        "-config",
        opensslConfiguration.path,
      ]
    )
    guard certificateResult.status == 0 else {
      throw RedirectFixtureError.setup("openssl failed: \(certificateResult.output)")
    }

    let serverScript = fixture.appendingPathComponent("loopback-release-server.py")
    try Self.loopbackServer.write(
      to: serverScript,
      atomically: true,
      encoding: .utf8
    )
    let serverLog = fixture.appendingPathComponent("server-process.log")
    _ = fileManager.createFile(atPath: serverLog.path, contents: nil)
    guard let serverOutput = FileHandle(forWritingAtPath: serverLog.path) else {
      throw RedirectFixtureError.setup("could not open the loopback server log")
    }
    defer { try? serverOutput.close() }

    let commit = String(repeating: "a", count: 40)
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    server.arguments = [
      "python3",
      serverScript.path,
      scenario,
      fixture.path,
      certificate.path,
      privateKey.path,
      Self.syntheticToken,
      commit,
    ]
    server.standardOutput = serverOutput
    server.standardError = serverOutput
    try server.run()
    defer {
      if server.isRunning {
        server.terminate()
      }
      server.waitUntilExit()
    }

    let readyFile = fixture.appendingPathComponent("server-ready.json")
    let deadline = Date().addingTimeInterval(5)
    while !fileManager.fileExists(atPath: readyFile.path) {
      if !server.isRunning {
        let output = (try? String(contentsOf: serverLog, encoding: .utf8)) ?? ""
        throw RedirectFixtureError.setup("loopback server exited early: \(output)")
      }
      guard Date() < deadline else {
        throw RedirectFixtureError.setup("loopback server did not become ready")
      }
      Thread.sleep(forTimeInterval: 0.02)
    }

    let readyData = try Data(contentsOf: readyFile)
    guard
      let ready = try JSONSerialization.jsonObject(with: readyData) as? [String: Int],
      let gitLabPort = ready["gitlab_port"]
    else {
      throw RedirectFixtureError.setup("loopback server returned malformed readiness data")
    }

    let gitLabOrigin = "https://127.0.0.1:\(gitLabPort)"
    let result = try runRedirectCommand(
      executable: "/bin/bash",
      arguments: [verifier.path],
      environment: [
        "CI_API_V4_URL": "\(gitLabOrigin)/api/v4",
        "CI_COMMIT_SHA": commit,
        "CI_COMMIT_TAG": "v0.2.0",
        "CI_JOB_TOKEN": Self.syntheticToken,
        "CI_PROJECT_ID": "42",
        "CI_SERVER_URL": gitLabOrigin,
        "CURL_CA_BUNDLE": certificate.path,
        "NO_PROXY": "127.0.0.1,localhost",
        "RELUX_GITLAB_PROJECT_ID": "42",
        "no_proxy": "127.0.0.1,localhost",
      ]
    )

    return RedirectExecution(
      result: result,
      gitLabRequests: readLog(named: "gitlab-requests.log", from: fixture),
      externalRequests: readLog(named: "external-requests.log", from: fixture)
    )
  }

  private func makeExecutable(_ file: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: file.path
    )
  }

  private func readLog(named name: String, from directory: URL) -> String {
    (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static let syntheticToken = "synthetic-job-token-do-not-forward"

  private static let opensslConfiguration = """
    [req]
    distinguished_name = distinguished_name
    x509_extensions = extensions
    prompt = no

    [distinguished_name]
    CN = 127.0.0.1

    [extensions]
    subjectAltName = IP:127.0.0.1
    basicConstraints = critical,CA:TRUE
    keyUsage = critical,digitalSignature,keyEncipherment,keyCertSign
    extendedKeyUsage = serverAuth
    """

  private static let loopbackServer = #"""
    import http.server
    import json
    import os
    import ssl
    import sys
    import threading
    import time
    from urllib.parse import urlparse

    scenario, root, certificate, private_key, token, commit = sys.argv[1:]
    assets = [
        "ReluxProxy-v0.2.0-universal.dmg",
        "ReluxProxy.dmg",
        "SHA256SUMS",
    ]

    def append_log(name, record):
        with open(os.path.join(root, name), "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, sort_keys=True) + "\n")

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, format, *args):
            return

        def send_bytes(self, status, body, content_type="application/octet-stream"):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def redirect(self, location):
            self.send_response(302)
            if location is not None:
                self.send_header("Location", location)
            self.send_header("Content-Length", "0")
            self.end_headers()

    class GitLabHandler(Handler):
        def do_GET(self):
            path = urlparse(self.path).path
            authenticated = self.headers.get("JOB-TOKEN") == token
            append_log(
                "gitlab-requests.log",
                {"path": path, "authenticated": authenticated},
            )
            if not authenticated:
                self.send_bytes(401, b"missing job token\n", "text/plain")
                return

            release_path = "/api/v4/projects/42/releases/v0.2.0"
            download_prefix = release_path + "/downloads/"
            if path == release_path:
                package_base = (
                    self.server.gitlab_origin
                    + "/api/v4/projects/42/packages/generic/relux-proxy/v0.2.0"
                )
                links = [
                    {
                        "name": asset,
                        "url": package_base + "/" + asset,
                        "direct_asset_path": "/" + asset,
                        "link_type": "package",
                    }
                    for asset in assets
                ]
                if scenario == "wrong-metadata":
                    links[0]["url"] = (
                        self.server.external_origin + "/objects/" + assets[0]
                    )
                body = json.dumps(
                    {
                        "tag_name": "v0.2.0",
                        "commit": {"id": commit},
                        "assets": {"links": links},
                    }
                ).encode("utf-8")
                self.send_bytes(200, body, "application/json")
                return

            if path.startswith(download_prefix):
                asset = path[len(download_prefix):]
                if asset not in assets:
                    self.send_bytes(404, b"unknown asset\n", "text/plain")
                    return
                if asset == assets[0]:
                    if scenario == "unsafe-http":
                        self.redirect(
                            "http://127.0.0.1:"
                            + str(self.server.external_port)
                            + "/objects/"
                            + asset
                        )
                    elif scenario == "missing-location":
                        self.redirect(None)
                    elif scenario == "malformed-location":
                        self.redirect("relative-object")
                    elif scenario == "excessive-redirects":
                        self.redirect("/redirect-loop/0")
                    elif scenario == "unexpected-status":
                        self.send_bytes(418, b"unexpected\n", "text/plain")
                    else:
                        self.redirect("/same-origin/" + asset)
                else:
                    self.redirect(self.server.external_origin + "/objects/" + asset)
                return

            if path.startswith("/redirect-loop/"):
                hop = int(path.rsplit("/", 1)[1])
                self.redirect("/redirect-loop/" + str(hop + 1))
                return

            if path.startswith("/same-origin/"):
                asset = path.rsplit("/", 1)[1]
                with open(os.path.join(root, "dist", asset), "rb") as handle:
                    self.send_bytes(200, handle.read())
                return

            self.send_bytes(404, b"not found\n", "text/plain")

    class ExternalHandler(Handler):
        def do_GET(self):
            path = urlparse(self.path).path
            token_present = self.headers.get("JOB-TOKEN") is not None
            append_log(
                "external-requests.log",
                {"path": path, "job_token_present": token_present},
            )
            if token_present:
                self.send_bytes(409, b"job token leaked\n", "text/plain")
                return
            if not path.startswith("/objects/"):
                self.send_bytes(404, b"not found\n", "text/plain")
                return
            asset = path.rsplit("/", 1)[1]
            if asset not in assets:
                self.send_bytes(404, b"unknown asset\n", "text/plain")
                return
            with open(os.path.join(root, "dist", asset), "rb") as handle:
                self.send_bytes(200, handle.read())

    gitlab = http.server.ThreadingHTTPServer(("127.0.0.1", 0), GitLabHandler)
    external = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ExternalHandler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certificate, private_key)
    gitlab.socket = context.wrap_socket(gitlab.socket, server_side=True)
    external.socket = context.wrap_socket(external.socket, server_side=True)

    gitlab_port = gitlab.server_address[1]
    external_port = external.server_address[1]
    gitlab.gitlab_origin = "https://127.0.0.1:" + str(gitlab_port)
    gitlab.external_origin = "https://127.0.0.1:" + str(external_port)
    gitlab.external_port = external_port

    ready = os.path.join(root, "server-ready.json")
    temporary_ready = ready + ".tmp"
    with open(temporary_ready, "w", encoding="utf-8") as handle:
        json.dump(
            {"gitlab_port": gitlab_port, "external_port": external_port},
            handle,
        )
    os.replace(temporary_ready, ready)

    threading.Thread(target=gitlab.serve_forever, daemon=True).start()
    threading.Thread(target=external.serve_forever, daemon=True).start()
    while True:
        time.sleep(1)
    """#
}

private struct RedirectExecution {
  let result: RedirectCommandResult
  let gitLabRequests: String
  let externalRequests: String
}

private struct RedirectCommandResult {
  let status: Int32
  let output: String
}

private enum RedirectFixtureError: Error {
  case setup(String)
}

private func runRedirectCommand(
  executable: String,
  arguments: [String],
  environment: [String: String] = [:],
  currentDirectory: URL? = nil
) throws -> RedirectCommandResult {
  let process = Process()
  let output = Pipe()

  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = currentDirectory
  process.standardOutput = output
  process.standardError = output
  process.environment = ProcessInfo.processInfo.environment.merging(environment) {
    _, replacement in replacement
  }

  try process.run()
  process.waitUntilExit()

  let data = output.fileHandleForReading.readDataToEndOfFile()
  return RedirectCommandResult(
    status: process.terminationStatus,
    output: String(decoding: data, as: UTF8.self)
  )
}
