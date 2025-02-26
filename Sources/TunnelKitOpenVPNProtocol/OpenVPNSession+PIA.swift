
import Foundation
import TunnelKitCore
import TunnelKitOpenVPNCore

extension OpenVPNSession {
    struct PIAHardReset {
        private static let obfuscationKeyLength = 3

        private static let magic = "53eo0rk92gxic98p1asgl5auh59r1vp4lmry1e3chzi100qntd"

        private static let encodedFormat = "\(magic)crypto\t%@|%@\tca\t%@"

        private let caMd5Digest: String

        private let cipherName: String

        private let digestName: String

        init(caMd5Digest: String, cipher: OpenVPN.Cipher, digest: OpenVPN.Digest) {
            self.caMd5Digest = caMd5Digest
            cipherName = cipher.rawValue.lowercased()
            digestName = digest.rawValue.lowercased()
        }

        // Ruby: pia_settings
        func encodedData() throws -> Data {
            guard let plainData = String(format: PIAHardReset.encodedFormat, cipherName, digestName, caMd5Digest).data(using: .ascii) else {
                fatalError("Unable to encode string to ASCII")
            }
            let keyBytes = try SecureRandom.data(length: PIAHardReset.obfuscationKeyLength)

            var encodedData = Data(keyBytes)
            for (i, b) in plainData.enumerated() {
                let keyChar = keyBytes[i % keyBytes.count]
                let xorredB = b ^ keyChar

                encodedData.append(xorredB)
            }
            return encodedData
        }
    }
}
