import Darwin
import Testing
@testable import NiceVoice

struct LocalServerEndpointTests {
    @Test
    func voxtralEndpointBuildsFromCustomPort() {
        let endpoint = TranscriptionEngine.voxtralLocal.makeLocalServerEndpoint(port: 8123)

        #expect(endpoint?.port == 8123)
        #expect(endpoint?.wsEndpoint == "ws://127.0.0.1:8123/v1/realtime")
        #expect(endpoint?.healthEndpoint == "http://127.0.0.1:8123/health")
    }

    @Test
    func resolvePortFallsBackWhenPreferredPortIsOccupied() throws {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        #expect(socketDescriptor >= 0)
        defer { close(socketDescriptor) }

        var reuseAddress: Int32 = 1
        setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(38080).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(
                    socketDescriptor,
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }

        #expect(bindResult == 0)
        #expect(listen(socketDescriptor, 1) == 0)

        let resolvedPort = LocalServerManager.resolvePort(
            preferred: 38080,
            fallbackRange: 38080...38082,
            serverCommand: "voxmlx-serve",
            serverPackagePath: ""
        )

        #expect(resolvedPort == 38081 || resolvedPort == 38082)
    }
}
