import Foundation
import Testing

@testable import ReluxProxy

@Suite
struct TunnelGuidanceTests {
  @Test
  func menuGuidanceLabelsTheApplicationProxyBoundary() {
    #expect(
      TunnelGuidance.endpointLabel
        == "Application SOCKS5 proxy — TCP only; not a system VPN or system-wide routing."
    )
    #expect(TunnelGuidance.clientHint.contains("SOCKS-aware app"))
    #expect(TunnelGuidance.clientHint.contains("proxy DNS / SOCKS5h"))
  }

  @Test
  func readmeAndCurrentStateUseTheSameEndpointBoundary() throws {
    let readme = try repositoryContents(at: "README.md")
    let currentState = try repositoryContents(at: "docs/current-state.md")

    #expect(normalizedWhitespace(readme).contains(TunnelGuidance.endpointLabel))
    #expect(normalizedWhitespace(currentState).contains(TunnelGuidance.endpointLabel))
  }

  @Test
  func reachabilityGuideCoversSafeDnsAndRemotePolicyChecks() throws {
    let guide = try repositoryContents(at: "docs/socks-vpn-reachability.md")

    for requiredText in [
      "SOCKS5 local DNS",
      "SOCKS5h / proxy DNS",
      "<PRIVATE_V4>",
      "<PRIVATE_HOST>",
      "--socks5-hostname",
      "`sshd` forwarding process",
      "firewall",
      "SOCKS-unaware",
      "UDP",
    ] {
      #expect(guide.contains(requiredText))
    }
  }

  private func repositoryContents(at relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }

  private func normalizedWhitespace(_ text: String) -> String {
    text.replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    )
  }
}
