import Foundation
import Testing

@Suite
struct PackagingAndUsageTests {
  @Test
  func sourceInfoPlistDefinesExpectedMenuBarApplication() throws {
    let data = try repositoryData(at: "Resources/Info.plist")
    let object = try PropertyListSerialization.propertyList(from: data, format: nil)
    let info = try #require(object as? [String: Any])

    #expect(info["CFBundleExecutable"] as? String == "ReluxProxy")
    #expect(info["CFBundleIdentifier"] as? String == "works.relux.proxy")
    #expect(info["CFBundlePackageType"] as? String == "APPL")
    #expect(info["LSMinimumSystemVersion"] as? String == "14.0")
    #expect(info["LSUIElement"] as? Bool == true)
  }

  @Test
  func appBuildRecipeCreatesAndVerifiesExpectedBundleLayout() throws {
    let script = try repositoryContents(at: "scripts/build-app.sh")

    for requiredText in [
      #""$BUNDLE/Contents/MacOS""#,
      #""$BUNDLE/Contents/Resources""#,
      #"cp "$BIN_DIR/ReluxProxy" "$BUNDLE/Contents/MacOS/ReluxProxy""#,
      #"cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist""#,
      #"codesign --verify --deep --strict --verbose=2 "$BUNDLE""#,
    ] {
      #expect(script.contains(requiredText))
    }
  }

  @Test
  func installedMacInstructionsCoverTwoEndpointsAndExitIdentity() throws {
    let readme = try repositoryContents(at: "README.md")

    for requiredText in [
      "Installed-Mac two-tunnel check",
      "127.0.0.1",
      "FIRST_SOCKS_PORT",
      "SECOND_SOCKS_PORT",
      "EXIT_IDENTITY_URL",
      "--socks5-hostname",
      "expected exit identity",
      "disconnect one profile",
      "not run by the automated test suite",
    ] {
      #expect(readme.contains(requiredText))
    }
  }

  private func repositoryData(at relativePath: String) throws -> Data {
    try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
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
