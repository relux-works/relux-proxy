import Darwin
import Testing

@testable import ReluxProxy

@Suite
struct LocalPortProbeTests {
  @Test
  func detectsAListenerAlreadyBoundToIPv4Loopback() throws {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    #expect(descriptor >= 0)
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        Darwin.bind(
          descriptor,
          socketAddress,
          socklen_t(MemoryLayout<sockaddr_in>.size)
        )
      }
    }
    #expect(bindResult == 0)
    #expect(listen(descriptor, 1) == 0)

    var boundAddress = sockaddr_in()
    var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        getsockname(descriptor, socketAddress, &boundLength)
      }
    }
    #expect(nameResult == 0)
    let port = Int(UInt16(bigEndian: boundAddress.sin_port))
    let probe = SystemLocalPortProbe()

    #expect(port > 0)
    #expect(!probe.isAvailable(port))
    #expect(probe.canConnect(port))
  }
}
