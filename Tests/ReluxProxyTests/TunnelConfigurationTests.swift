import XCTest
@testable import ReluxProxy

final class TunnelConfigurationTests: XCTestCase {
    func testBuildsTargetWithAccount() throws {
        let configuration = TunnelConfiguration(
            host: " relux ",
            account: " administrator ",
            localPort: 1_080
        )

        XCTAssertEqual(configuration.target, "administrator@relux")
        XCTAssertEqual(configuration.localEndpoint, "127.0.0.1:1080")
        XCTAssertNil(configuration.validationError)
    }

    func testBuildsTargetWithoutAccount() {
        let configuration = TunnelConfiguration(host: "relux", account: "", localPort: 9_050)
        XCTAssertEqual(configuration.target, "relux")
    }

    func testRejectsInvalidValues() {
        XCTAssertNotNil(TunnelConfiguration(host: "", account: "user", localPort: 1_080).validationError)
        XCTAssertNotNil(TunnelConfiguration(host: "bad host", account: "user", localPort: 1_080).validationError)
        XCTAssertNotNil(TunnelConfiguration(host: "host", account: "bad@user", localPort: 1_080).validationError)
        XCTAssertNotNil(TunnelConfiguration(host: "host", account: "user", localPort: 70_000).validationError)
    }

    func testSSHArgumentsMatchHardenedTunnelSetup() throws {
        let configuration = TunnelConfiguration(host: "relux", account: "administrator", localPort: 1_080)
        let arguments = try SSHCommandBuilder.arguments(for: configuration)

        XCTAssertEqual(
            arguments,
            [
                "-N",
                "-C",
                "-D", "127.0.0.1:1080",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=30",
                "-o", "ServerAliveCountMax=3",
                "-o", "ConnectTimeout=15",
                "-o", "BatchMode=yes",
                "-o", "LogLevel=ERROR",
                "administrator@relux",
            ]
        )
    }
}
