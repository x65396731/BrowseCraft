import CommonCrypto
import Foundation
import BrowseCraftCore

// 中文注释：CommonCryptoResourcePipelineCryptography 是 Infrastructure 对 V2 pipeline 密码学协议的唯一实现。

enum CommonCryptoResourcePipelineError: LocalizedError, Equatable {
    case invalidAESKeyLength(Int)
    case invalidAESIVLength(Int)
    case decryptFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidAESKeyLength(let length):
            return "Invalid AES key length: \(length)"
        case .invalidAESIVLength(let length):
            return "Invalid AES IV length: \(length)"
        case .decryptFailed(let status):
            return "CommonCrypto decrypt failed: status=\(status)"
        }
    }
}

struct CommonCryptoResourcePipelineCryptography: ResourcePipelineCryptography {
    func hash(_ data: Data, algorithm: ResourceHashAlgorithm) throws -> Data {
        switch algorithm {
        case .sha256:
            var digest: [UInt8] = Array(repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes { bytes in
                digest.withUnsafeMutableBufferPointer { buffer in
                    _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), buffer.baseAddress)
                }
            }
            return Data(digest)
        case .sha512:
            var digest: [UInt8] = Array(repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
            data.withUnsafeBytes { bytes in
                digest.withUnsafeMutableBufferPointer { buffer in
                    _ = CC_SHA512(bytes.baseAddress, CC_LONG(data.count), buffer.baseAddress)
                }
            }
            return Data(digest)
        }
    }

    func decrypt(
        _ ciphertext: Data,
        algorithm: ResourceCipherAlgorithm,
        mode: ResourceCipherMode,
        padding: ResourceCipherPadding,
        key: Data,
        iv: Data
    ) throws -> Data {
        switch algorithm {
        case .aes:
            break
        }
        switch mode {
        case .cbc:
            break
        }

        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(key.count) else {
            throw CommonCryptoResourcePipelineError.invalidAESKeyLength(key.count)
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw CommonCryptoResourcePipelineError.invalidAESIVLength(iv.count)
        }

        let options: CCOptions
        switch padding {
        case .pkcs7:
            options = CCOptions(kCCOptionPKCS7Padding)
        case .none:
            options = 0
        }

        let outputCapacity: Int = ciphertext.count + kCCBlockSizeAES128
        var output: Data = Data(count: outputCapacity)
        var outputLength: size_t = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            options,
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw CommonCryptoResourcePipelineError.decryptFailed(status)
        }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}
