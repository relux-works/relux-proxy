import Foundation
import Testing

@testable import ReluxProxy

@Suite
struct TunnelConfigurationTests {
  @Test
  func normalizesDisplayTargetAndLocalEndpoint() {
    let configuration = TunnelConfiguration(
      host: " work-bastion ",
      account: " ops ",
      localPort: 1_080
    )

    #expect(configuration.target == "ops@work-bastion")
    #expect(configuration.sshDestination == "work-bastion")
    #expect(configuration.localEndpoint == "127.0.0.1:1080")
    #expect(configuration.validationError == nil)
  }

  @Test(arguments: ["203.0.113.10", "bastion.example.net", "work-bastion"])
  func emptyAccountPassesBareDestination(_ host: String) throws {
    let configuration = TunnelConfiguration(host: host, account: "", localPort: 9_050)
    let arguments = try SSHCommandBuilder.arguments(for: configuration)

    #expect(configuration.target == host)
    #expect(arguments.last == host)
    #expect(!arguments.contains("-l"))
  }

  @Test(arguments: ["203.0.113.10", "bastion.example.net", "work-bastion"])
  func accountUsesSeparateUserOverride(_ host: String) throws {
    let configuration = TunnelConfiguration(host: host, account: "ops", localPort: 9_050)
    let arguments = try SSHCommandBuilder.arguments(for: configuration)

    #expect(configuration.target == "ops@\(host)")
    #expect(arguments.suffix(3) == ["-l", "ops", host])
    #expect(!arguments.contains("ops@\(host)"))
  }

  @Test
  func shellMetacharactersRemainLiteralArgumentsWithoutAShell() throws {
    let host = "alias;echo${IFS}unexpected"
    let account = "ops$(id)"
    let configuration = TunnelConfiguration(host: host, account: account, localPort: 9_050)
    let arguments = try SSHCommandBuilder.arguments(for: configuration)

    #expect(SSHCommandBuilder.executableURL.path == "/usr/bin/ssh")
    #expect(arguments.suffix(3) == ["-l", account, host])
    #expect(arguments.filter { $0 == host }.count == 1)
    #expect(arguments.filter { $0 == account }.count == 1)
    #expect(!arguments.contains("/bin/sh"))
    #expect(!arguments.contains("-c"))
  }

  @Test
  func rejectsInvalidValues() {
    #expect(
      TunnelConfiguration(host: "", account: "user", localPort: 1_080)
        .validationError != nil
    )
    #expect(
      TunnelConfiguration(host: "bad host", account: "user", localPort: 1_080)
        .validationError != nil
    )
    #expect(
      TunnelConfiguration(host: "-oProxyCommand=x", account: "user", localPort: 1_080)
        .validationError != nil
    )
    #expect(
      TunnelConfiguration(host: "host", account: "bad@user", localPort: 1_080)
        .validationError != nil
    )
    #expect(
      TunnelConfiguration(host: "host", account: "user", localPort: 70_000)
        .validationError != nil
    )
  }

  @Test
  func buildsExactHardenedArgumentsWithLocalOnlyBinding() throws {
    let configuration = TunnelConfiguration(
      host: "work-bastion",
      account: "administrator",
      localPort: 1_080
    )

    #expect(
      try SSHCommandBuilder.arguments(for: configuration) == [
        "-N",
        "-C",
        "-D", "127.0.0.1:1080",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-o", "ConnectTimeout=15",
        "-o", "BatchMode=yes",
        "-o", "LogLevel=ERROR",
        "-l", "administrator",
        "work-bastion",
      ]
    )
  }

  @Test
  func guidanceLeavesTheOpenSSHDynamicForwardContractUnchanged() throws {
    let configuration = TunnelConfiguration(
      host: "work-bastion",
      account: "",
      localPort: 1_080
    )
    let arguments = try SSHCommandBuilder.arguments(for: configuration)

    #expect(SSHCommandBuilder.executableURL.path == "/usr/bin/ssh")
    #expect(Array(arguments.prefix(4)) == ["-N", "-C", "-D", "127.0.0.1:1080"])
    #expect(!arguments.contains("-w"))
  }

  @Test
  func invalidConfigurationDoesNotProduceArguments() {
    let configuration = TunnelConfiguration(
      host: "-oProxyCommand=unexpected",
      account: "",
      localPort: 1_080
    )
    let expectedMessage = configuration.validationError ?? ""

    #expect(throws: SSHCommandError.self) {
      try SSHCommandBuilder.arguments(for: configuration)
    }
    #expect(!expectedMessage.isEmpty)
    #expect(
      SSHCommandError.invalidConfiguration(expectedMessage).errorDescription
        == expectedMessage
    )
  }
}
