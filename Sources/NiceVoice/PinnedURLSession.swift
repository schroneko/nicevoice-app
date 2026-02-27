import Foundation
import CommonCrypto
import Security

final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedHost = "nukosuku.com"

    private static let ecP256SPKIHeader: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02,
        0x01, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00,
    ]

    private static let ecP384SPKIHeader: [UInt8] = [
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02,
        0x01, 0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00,
    ]

    private var pinnedKeyHashes: Set<Data> {
        var hashes = Set<Data>()
        if let leafData = Data(base64Encoded: ObfuscatedStrings.certPinLeaf) {
            hashes.insert(leafData)
        }
        if let intermediateData = Data(base64Encoded: ObfuscatedStrings.certPinIntermediate) {
            hashes.insert(intermediateData)
        }
        return hashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == pinnedHost,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var matched = false

        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let pins = pinnedKeyHashes

        for certificate in certificateChain {
            guard let publicKey = SecCertificateCopyKey(certificate) else {
                continue
            }

            guard let rawKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                continue
            }

            guard let spkiHeader = spkiHeader(for: rawKeyData) else {
                continue
            }

            var spkiData = Data(spkiHeader)
            spkiData.append(rawKeyData)

            let spkiHash = sha256(spkiData)
            if pins.contains(spkiHash) {
                matched = true
                break
            }
        }

        if matched {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            debugLog("Certificate pin validation failed for \(pinnedHost)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func spkiHeader(for rawKeyData: Data) -> [UInt8]? {
        switch rawKeyData.count {
        case 65:
            return Self.ecP256SPKIHeader
        case 97:
            return Self.ecP384SPKIHeader
        default:
            return nil
        }
    }

    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash)
    }
}
