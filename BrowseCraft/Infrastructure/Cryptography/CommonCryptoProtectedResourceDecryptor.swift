import CommonCrypto
import Foundation
import BrowseCraftCore

/// 中文注释：受保护资源旧链路的 CommonCrypto adapter，保持原有错误类型与校验顺序。
struct CommonCryptoProtectedResourceDecryptor: ProtectedResourceDecrypting {
    func sha512(_ data: Data) -> Data {
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            digest.withUnsafeMutableBufferPointer { buffer in
                _ = CC_SHA512(bytes.baseAddress, CC_LONG(data.count), buffer.baseAddress)
            }
        }
        return Data(digest)
    }

    func decrypt(ciphertext: Data, rule: ProtectedResourceDecryptRule, key: Data, iv: Data?) throws -> Data {
        guard rule.algorithm == .aes else {
            throw ProtectedResourceRuntimeError.unsupportedDecryptConfiguration(
                reason: "algorithm=\(rule.algorithm.rawValue)"
            )
        }

        guard rule.mode == .cbc else {
            throw ProtectedResourceRuntimeError.unsupportedDecryptConfiguration(
                reason: "mode=\(rule.mode.rawValue)"
            )
        }

        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(key.count) else {
            throw ProtectedResourceRuntimeError.unsupportedDecryptConfiguration(
                reason: "invalidAESKeyLength=\(key.count)"
            )
        }

        guard let iv: Data = iv,
              iv.count == kCCBlockSizeAES128 else {
            throw ProtectedResourceRuntimeError.unsupportedDecryptConfiguration(
                reason: "invalidAESIVLength=\(iv?.count ?? 0)"
            )
        }

        let padding: ProtectedResourcePadding = rule.padding ?? .pkcs7
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
            throw ProtectedResourceRuntimeError.decryptFailed(reason: "ccStatus=\(status)")
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }
}
