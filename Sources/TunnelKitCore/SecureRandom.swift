
import Foundation
import Security.SecRandom
import CTunnelKitCore
import __TunnelKitUtils

/// Errors returned by `SecureRandom`.
public enum SecureRandomError: Error {

    /// RNG could not be initialized.
    case randomGenerator
}

/// Generates random data in a secure fashion.
public class SecureRandom {

    @available(*, deprecated)
    static func uint32FromBuffer() throws -> UInt32 {
        var randomBuffer = [UInt8](repeating: 0, count: 4)

        guard SecRandomCopyBytes(kSecRandomDefault, 4, &randomBuffer) == 0 else {
            throw TunnelKitCoreError.secureRandom(.randomGenerator)
        }

        var randomNumber: UInt32 = 0
        for i in 0..<4 {
            let byte = randomBuffer[i]
            randomNumber |= (UInt32(byte) << UInt32(8 * i))
        }
        return randomNumber
    }

    public static func uint32() throws -> UInt32 {
        var randomNumber: UInt32 = 0

        try withUnsafeMutablePointer(to: &randomNumber) {
            try $0.withMemoryRebound(to: UInt8.self, capacity: 4) { (randomBytes: UnsafeMutablePointer<UInt8>) -> Void in
                guard SecRandomCopyBytes(kSecRandomDefault, 4, randomBytes) == 0 else {
                    throw TunnelKitCoreError.secureRandom(.randomGenerator)
                }
            }
        }

        return randomNumber
    }

    public static func data(length: Int) throws -> Data {
        var randomData = Data(count: length)

        try randomData.withUnsafeMutableBytes {
            let randomBytes = $0.bytePointer
            guard SecRandomCopyBytes(kSecRandomDefault, length, randomBytes) == 0 else {
                throw TunnelKitCoreError.secureRandom(.randomGenerator)
            }
        }

        return randomData
    }

    public static func safeData(length: Int) throws -> ZeroingData {
        let randomBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        defer {
//            randomBytes.initialize(to: 0, count: length)
            bzero(randomBytes, length)
            randomBytes.deallocate()
        }

        guard SecRandomCopyBytes(kSecRandomDefault, length, randomBytes) == 0 else {
            throw TunnelKitCoreError.secureRandom(.randomGenerator)
        }

        return Z(bytes: randomBytes, count: length)
    }
}
