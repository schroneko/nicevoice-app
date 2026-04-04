import Foundation
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
    func resolvedPortReadsNiceVoiceMarker() {
        let resolvedPort = LocalServerManager.resolvedPort(from: "NICEVOICE_PORT=45678")

        #expect(resolvedPort == 45678)
    }

    @Test
    func currentLocalServerEndpointUsesStoredPort() {
        let key = "localServerPort.voxtralLocal"
        UserDefaults.standard.set(45678, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let endpoint = TranscriptionEngine.voxtralLocal.currentLocalServerEndpoint

        #expect(endpoint?.port == 45678)
        #expect(endpoint?.wsEndpoint == "ws://127.0.0.1:45678/v1/realtime")
    }

    @Test
    func resolvedPortReadsUvicornLogLine() {
        let resolvedPort = LocalServerManager.resolvedPort(
            from: "INFO:     Uvicorn running on http://127.0.0.1:53748 (Press CTRL+C to quit)"
        )

        #expect(resolvedPort == 53748)
    }
}
