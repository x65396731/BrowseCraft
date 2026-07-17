import CommonCrypto
import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：ResourcePipelineExecutorTests 验证 V2 通用 pipeline，不通过 Reader 或旧 ProtectedResourceLoader 接线。
struct ResourcePipelineExecutorTests {
    @Test func executorRunsGenericEnvelopeAndImageDecryptPipeline() async throws {
        let secret: String = "reader-secret-value"
        let digest: Data = Self.hashSHA512(Data(secret.utf8))
        let envelopeKey: Data = Data(digest.prefix(32))
        let envelopeIV: Data = Data(digest.dropFirst(32).prefix(16))
        let imageKey: Data = Data("12345678901234567890123456789012".utf8)
        let imageIV: Data = Data("abcdefghijklmnop".utf8)
        let envelopePlaintext: Data = Data(
            "\(String(decoding: imageKey, as: UTF8.self)):\(String(decoding: imageIV, as: UTF8.self))".utf8
        )
        let encryptedEnvelope: Data = try Self.encrypt(
            envelopePlaintext,
            key: envelopeKey,
            iv: envelopeIV
        )
        let imageData: Data = Data([0x89, 0x50, 0x4E, 0x47]) + Data("generic-pipeline-image".utf8)
        let imageDataURL: Data = Data(
            "data:image/png;base64,\(imageData.base64EncodedString())".utf8
        )
        let encryptedImage: Data = try Self.encrypt(imageDataURL, key: imageKey, iv: imageIV)
        let loader: RecordingResourcePipelineDataLoader = RecordingResourcePipelineDataLoader(
            responses: [
                "https://api.example.test/key/123": Data(
                    #"{"data":{"key":"\#(encryptedEnvelope.base64EncodedString())"}}"#.utf8
                ),
                "https://cdn.example.test/encrypt/123/2": encryptedImage
            ]
        )
        let rule: ResourcePipelineRule = try JSONDecoder().decode(
            ResourcePipelineRule.self,
            from: Data(Self.pipelineJSON.utf8)
        )
        let executor: ResourcePipelineExecutor = ResourcePipelineExecutor(
            dataLoader: loader,
            cryptography: CommonCryptoResourcePipelineCryptography()
        )

        let output: ResourcePipelineExecutionOutput = try await executor.execute(
            ResourcePipelineExecutionInput(
                rule: rule,
                sourceID: "generic-test-source",
                item: ["id": .string("123")],
                context: ["readerAccessToken": .string("guest-secret")],
                requestContext: SourceRequestContext(
                    sourceID: "generic-test-source",
                    baseURL: URL(string: "https://example.test")!,
                    purpose: .image,
                    contextValues: ["readerAccessToken": secret]
                )
            )
        )

        #expect(output.contentType == .image)
        #expect(output.data == imageData)
        #expect(loader.requests.map(\.url.absoluteString) == [
            "https://api.example.test/key/123",
            "https://cdn.example.test/encrypt/123/2"
        ])
        #expect(loader.requests.map { $0.context?.purpose } == [
            .protectedResource,
            .protectedResource
        ])
        #expect(loader.requests.first?.request?.headers?["device"] == "server")
    }

    @Test func cccCompatibilityPipelinePreservesLegacySubstringOffsetSemantics() async throws {
        let secret: String = "freeforccc2020reading"
        let digest: Data = Self.hashSHA512(Data(secret.utf8))
        let envelopeKey: Data = Data(digest.prefix(32))
        // substring(30, 32) operates on SHA-512 hex characters, so the IV starts at byte 15.
        let envelopeIV: Data = Data(digest.dropFirst(15).prefix(16))
        let imageKey: Data = Data("12345678901234567890123456789012".utf8)
        let imageIV: Data = Data("abcdefghijklmnop".utf8)
        let encryptedEnvelope: Data = try Self.encrypt(
            Data(
                "\(String(decoding: imageKey, as: UTF8.self)):\(String(decoding: imageIV, as: UTF8.self))".utf8
            ),
            key: envelopeKey,
            iv: envelopeIV
        )
        let imageData: Data = Data([0x89, 0x50, 0x4E, 0x47]) + Data("ccc-compatibility".utf8)
        let encryptedImage: Data = try Self.encrypt(
            Data("data:image/png;base64,\(imageData.base64EncodedString())".utf8),
            key: imageKey,
            iv: imageIV
        )
        let loader: RecordingResourcePipelineDataLoader = RecordingResourcePipelineDataLoader(
            responses: [
                "https://api.creative-comic.tw/book/chapter/image/image-7": Data(
                    #"{"data":{"key":"\#(encryptedEnvelope.base64EncodedString())"}}"#.utf8
                ),
                "https://www.creative-comic.tw/fs/chapter_content/encrypt/image-7/2": encryptedImage
            ]
        )
        let rule: ResourcePipelineRule = try JSONDecoder().decode(
            ResourcePipelineRule.self,
            from: Data(Self.cccCompatibilityPipelineJSON.utf8)
        )
        let executor: ResourcePipelineExecutor = ResourcePipelineExecutor(
            dataLoader: loader,
            cryptography: CommonCryptoResourcePipelineCryptography()
        )

        let output: ResourcePipelineExecutionOutput = try await executor.execute(
            ResourcePipelineExecutionInput(
                rule: rule,
                sourceID: "compatibility-test-source",
                item: ["id": .string("image-7")],
                context: ["readerAccessToken": .string(secret)]
            )
        )

        #expect(output.data == imageData)
        #expect(loader.requests.map(\.url.absoluteString) == [
            "https://api.creative-comic.tw/book/chapter/image/image-7",
            "https://www.creative-comic.tw/fs/chapter_content/encrypt/image-7/2"
        ])
    }

    @Test func invalidGraphFailsBeforeFirstRequest() async throws {
        let loader: RecordingResourcePipelineDataLoader = RecordingResourcePipelineDataLoader(responses: [:])
        let rule: ResourcePipelineRule = ResourcePipelineRule(
            bindings: [:],
            steps: [
                ResourcePipelineStepRule(
                    id: "wouldRequest",
                    operation: .request(
                        ResourceRequestOperationRule(
                            urlTemplate: "https://example.test/data",
                            responseType: .data
                        )
                    )
                ),
                ResourcePipelineStepRule(
                    id: "invalidDecode",
                    operation: .decode(
                        ResourceDecodeOperationRule(
                            input: ResourceValueReferenceRule(source: .step, name: "futureStep"),
                            encoding: .raw
                        )
                    )
                )
            ],
            output: ResourcePipelineOutputRule(
                value: ResourceValueReferenceRule(source: .step, name: "wouldRequest"),
                contentType: .binary
            )
        )
        let executor: ResourcePipelineExecutor = ResourcePipelineExecutor(
            dataLoader: loader,
            cryptography: CommonCryptoResourcePipelineCryptography()
        )

        do {
            _ = try await executor.execute(
                ResourcePipelineExecutionInput(rule: rule, sourceID: "invalid-graph")
            )
            Issue.record("Expected graph validation to fail")
        } catch let error as ResourcePipelineExecutorError {
            #expect(error == .missingReference(source: .step, name: "futureStep"))
        }
        #expect(loader.requests.isEmpty)
    }

    @Test func unresolvedTemplateFailsWithoutNetworkRequest() async throws {
        let loader: RecordingResourcePipelineDataLoader = RecordingResourcePipelineDataLoader(responses: [:])
        let rule: ResourcePipelineRule = ResourcePipelineRule(
            bindings: [
                "imageId": ResourceBindingRule(source: .item, path: "id")
            ],
            steps: [
                ResourcePipelineStepRule(
                    id: "request",
                    operation: .request(
                        ResourceRequestOperationRule(
                            urlTemplate: "https://example.test/{binding.quality}",
                            responseType: .data
                        )
                    )
                )
            ],
            output: ResourcePipelineOutputRule(
                value: ResourceValueReferenceRule(source: .step, name: "request"),
                contentType: .binary
            )
        )
        let executor: ResourcePipelineExecutor = ResourcePipelineExecutor(
            dataLoader: loader,
            cryptography: CommonCryptoResourcePipelineCryptography()
        )

        do {
            _ = try await executor.execute(
                ResourcePipelineExecutionInput(
                    rule: rule,
                    sourceID: "unresolved-template",
                    item: ["id": .string("123")]
                )
            )
            Issue.record("Expected template resolution to fail")
        } catch let error as ResourcePipelineExecutorError {
            #expect(error == .unresolvedTemplateToken("binding.quality"))
        }
        #expect(loader.requests.isEmpty)
    }

    @Test func commonCryptoProviderHashesAndRejectsInvalidAESMaterial() throws {
        let provider: CommonCryptoResourcePipelineCryptography = CommonCryptoResourcePipelineCryptography()
        let digest: Data = try provider.hash(Data("abc".utf8), algorithm: .sha256)

        #expect(digest.map { String(format: "%02x", $0) }.joined() ==
            "ba7816bf8f01cfea414140de5dae2223" +
            "b00361a396177a9cb410ff61f20015ad")
        #expect(throws: CommonCryptoResourcePipelineError.invalidAESKeyLength(5)) {
            _ = try provider.decrypt(
                Data(repeating: 0, count: 16),
                algorithm: .aes,
                mode: .cbc,
                padding: .none,
                key: Data(repeating: 0, count: 5),
                iv: Data(repeating: 0, count: 16)
            )
        }
    }

    @Test func integerNumberBindingRendersWithoutFractionalSuffix() async throws {
        try await Self.expectNumberBinding(
            99_985,
            expectedURL: "https://example.test/image/99985/2"
        )
    }

    @Test func fractionalNumberBindingPreservesFractionalComponent() async throws {
        try await Self.expectNumberBinding(
            2.5,
            expectedURL: "https://example.test/image/2.5/2"
        )
    }

    @Test func negativeZeroNumberBindingRendersAsZero() async throws {
        try await Self.expectNumberBinding(
            -0.0,
            expectedURL: "https://example.test/image/0/2"
        )
    }

    private static func expectNumberBinding(
        _ value: Double,
        expectedURL: String
    ) async throws {
        let response: Data = Data("resource".utf8)
        let loader: RecordingResourcePipelineDataLoader = RecordingResourcePipelineDataLoader(
            responses: [expectedURL: response]
        )
        let rule: ResourcePipelineRule = ResourcePipelineRule(
            bindings: [
                "imageId": ResourceBindingRule(source: .item, path: "id"),
                "quality": ResourceBindingRule(source: .constant, value: "2")
            ],
            steps: [
                ResourcePipelineStepRule(
                    id: "resource",
                    operation: .request(
                        ResourceRequestOperationRule(
                            urlTemplate: "https://example.test/image/{binding.imageId}/{binding.quality}",
                            responseType: .data
                        )
                    )
                )
            ],
            output: ResourcePipelineOutputRule(
                value: ResourceValueReferenceRule(source: .step, name: "resource"),
                contentType: .binary
            )
        )
        let executor: ResourcePipelineExecutor = ResourcePipelineExecutor(
            dataLoader: loader,
            cryptography: CommonCryptoResourcePipelineCryptography()
        )

        let output: ResourcePipelineExecutionOutput = try await executor.execute(
            ResourcePipelineExecutionInput(
                rule: rule,
                sourceID: "number-binding-test",
                item: ["id": .number(value)]
            )
        )

        #expect(output.data == response)
        #expect(loader.requests.map(\.url.absoluteString) == [expectedURL])
    }

    private static func hashSHA512(_ data: Data) -> Data {
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            digest.withUnsafeMutableBufferPointer { buffer in
                _ = CC_SHA512(bytes.baseAddress, CC_LONG(data.count), buffer.baseAddress)
            }
        }
        return Data(digest)
    }

    private static func encrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
        let outputCapacity: Int = plaintext.count + kCCBlockSizeAES128
        var output: Data = Data(count: outputCapacity)
        var outputLength: size_t = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            plaintext.withUnsafeBytes { plaintextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            plaintextBytes.baseAddress,
                            plaintext.count,
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

    private static let pipelineJSON = #"""
    {
      "version": 2,
      "bindings": {
        "imageId": { "source": "item", "path": "id" },
        "quality": { "source": "constant", "value": "2" },
        "device": { "source": "constant", "value": "server" },
        "readerSecret": { "source": "context", "path": "readerAccessToken" }
      },
      "steps": [
        {
          "id": "keyResponse",
          "operation": {
            "type": "request",
            "urlTemplate": "https://api.example.test/key/{binding.imageId}",
            "request": {
              "method": "GET",
              "headers": { "device": "{binding.device}" }
            },
            "responseType": "json"
          }
        },
        {
          "id": "envelope",
          "operation": {
            "type": "extract",
            "input": { "source": "step", "name": "keyResponse" },
            "path": "data.key",
            "outputType": "string"
          }
        },
        {
          "id": "envelopeCiphertext",
          "operation": {
            "type": "decode",
            "input": { "source": "step", "name": "envelope" },
            "encoding": "base64"
          }
        },
        {
          "id": "secretDigest",
          "operation": {
            "type": "hash",
            "input": { "source": "binding", "name": "readerSecret" },
            "algorithm": "SHA512",
            "outputEncoding": "hex"
          }
        },
        {
          "id": "envelopeKeyHex",
          "operation": {
            "type": "slice",
            "input": { "source": "step", "name": "secretDigest" },
            "offset": 0,
            "length": 64,
            "unit": "characters"
          }
        },
        {
          "id": "envelopeIVHex",
          "operation": {
            "type": "slice",
            "input": { "source": "step", "name": "secretDigest" },
            "offset": 64,
            "length": 32,
            "unit": "characters"
          }
        },
        {
          "id": "envelopeKey",
          "operation": {
            "type": "decode",
            "input": { "source": "step", "name": "envelopeKeyHex" },
            "encoding": "hex"
          }
        },
        {
          "id": "envelopeIV",
          "operation": {
            "type": "decode",
            "input": { "source": "step", "name": "envelopeIVHex" },
            "encoding": "hex"
          }
        },
        {
          "id": "keyMaterialText",
          "operation": {
            "type": "decrypt",
            "input": { "source": "step", "name": "envelopeCiphertext" },
            "algorithm": "AES",
            "mode": "CBC",
            "padding": "PKCS7",
            "key": { "source": "step", "name": "envelopeKey" },
            "iv": { "source": "step", "name": "envelopeIV" }
          }
        },
        {
          "id": "keyMaterial",
          "operation": {
            "type": "split",
            "input": { "source": "step", "name": "keyMaterialText" },
            "delimiter": ":",
            "fields": ["key", "iv"],
            "omittingEmptySubsequences": false
          }
        },
        {
          "id": "ciphertext",
          "operation": {
            "type": "request",
            "urlTemplate": "https://cdn.example.test/encrypt/{binding.imageId}/{binding.quality}",
            "responseType": "data"
          }
        },
        {
          "id": "plaintext",
          "operation": {
            "type": "decrypt",
            "input": { "source": "step", "name": "ciphertext" },
            "algorithm": "AES",
            "mode": "CBC",
            "padding": "PKCS7",
            "key": { "source": "step", "name": "keyMaterial", "path": "key" },
            "iv": { "source": "step", "name": "keyMaterial", "path": "iv" }
          }
        },
        {
          "id": "imageData",
          "operation": {
            "type": "decode",
            "input": { "source": "step", "name": "plaintext" },
            "encoding": "dataURLBase64"
          }
        }
      ],
      "output": {
        "value": { "source": "step", "name": "imageData" },
        "contentType": "image"
      }
    }
    """#

    private static var cccCompatibilityPipelineJSON: String {
        return self.pipelineJSON
            .replacingOccurrences(
                of: "https://api.example.test/key/{binding.imageId}",
                with: "https://api.creative-comic.tw/book/chapter/image/{binding.imageId}"
            )
            .replacingOccurrences(
                of: "https://cdn.example.test/encrypt/{binding.imageId}/{binding.quality}",
                with: "https://www.creative-comic.tw/fs/chapter_content/encrypt/{binding.imageId}/{binding.quality}"
            )
            .replacingOccurrences(
                of: #""offset": 64,"#,
                with: #""offset": 30,"#
            )
    }
}

private final class RecordingResourcePipelineDataLoader: ContextualPageDataLoader {
    struct Request {
        let url: URL
        let request: RequestConfig?
        let context: SourceRequestContext?
    }

    private let responses: [String: Data]
    private(set) var requests: [Request] = []

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func getData(from url: URL, request: RequestConfig?) async throws -> Data {
        return try await self.getData(from: url, request: request, context: nil)
    }

    func getData(
        from url: URL,
        request: RequestConfig?,
        context: SourceRequestContext?
    ) async throws -> Data {
        self.requests.append(Request(url: url, request: request, context: context))
        guard let data: Data = self.responses[url.absoluteString] else {
            throw URLError(.fileDoesNotExist)
        }
        return data
    }
}
