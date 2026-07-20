import CommonCrypto
import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：ProtectedResourceRuntime 测试，覆盖 key 请求、二进制请求、AES 解密和错误分类。
struct ProtectedResourceRuntimeTests {
    @Test func loaderFetchesKeyAndBinaryThenDecryptsAESCBCPKCS7() async throws {
        let key: Data = Data("12345678901234567890123456789012".utf8)
        let iv: Data = Data("abcdefghijklmnop".utf8)
        let plaintext: Data = Data([0x89, 0x50, 0x4E, 0x47]) + Data("decoded-image".utf8)
        let ciphertext: Data = try Self.crypt(
            operation: CCOperation(kCCEncrypt),
            input: plaintext,
            key: key,
            iv: iv
        )
        let loader: RecordingProtectedResourceDataLoader = RecordingProtectedResourceDataLoader(
            responses: [
                "https://api.example.test/key/123": Data(
                    """
                    {"data":{"key":"\(key.base64EncodedString())","iv":"\(iv.base64EncodedString())"}}
                    """.utf8
                ),
                "https://api.example.test/binary/123/high": ciphertext
            ]
        )
        let runtime: ProtectedResourceLoader = ProtectedResourceLoader(
            dataLoader: loader,
            decryptor: CommonCryptoProtectedResourceDecryptor()
        )
        let rule: ProtectedResourceRule = ProtectedResourceRule(
            type: .encryptedBinary,
            keyRequest: ProtectedResourceRequestRule(
                url: "https://api.example.test/key/{imageId}",
                request: RequestConfig(headers: ["device": "server"])
            ),
            keyPath: "data.key",
            binaryRequest: ProtectedResourceRequestRule(
                url: "https://api.example.test/binary/{imageId}/{quality}"
            ),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .cbc,
                padding: .pkcs7,
                key: ProtectedResourceValueRule(
                    source: .keyResponse,
                    encoding: .base64
                ),
                iv: ProtectedResourceValueRule(
                    source: .keyResponse,
                    path: "data.iv",
                    encoding: .base64
                ),
                ciphertextEncoding: .raw
            ),
            output: ProtectedResourceOutputRule(contentType: .image)
        )

        let output: ProtectedResourceOutput = try await runtime.load(
            ProtectedResourceLoadInput(
                rule: rule,
                sourceID: "example",
                parameters: [
                    "imageId": "123",
                    "quality": "high"
                ],
                context: SourceRequestContext(
                    sourceID: "example",
                    baseURL: try #require(URL(string: "https://example.test")),
                    purpose: .image
                )
            )
        )

        #expect(output.contentType == .image)
        #expect(output.data == plaintext)
        #expect(loader.requests.map(\.url.absoluteString) == [
            "https://api.example.test/key/123",
            "https://api.example.test/binary/123/high"
        ])
        #expect(loader.requests.map { $0.context?.purpose } == [.protectedResource, .image])
        #expect(loader.requests.first?.request?.headers?["device"] == "server")
    }

    @Test func unsupportedCipherModeIsClassifiedAsProtectedResourceError() async throws {
        let loader: RecordingProtectedResourceDataLoader = RecordingProtectedResourceDataLoader(
            responses: [
                "https://api.example.test/binary/123": Data("cipher".utf8)
            ]
        )
        let runtime: ProtectedResourceLoader = ProtectedResourceLoader(
            dataLoader: loader,
            decryptor: CommonCryptoProtectedResourceDecryptor()
        )
        let rule: ProtectedResourceRule = ProtectedResourceRule(
            type: .encryptedBinary,
            binaryRequest: ProtectedResourceRequestRule(url: "https://api.example.test/binary/{imageId}"),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .gcm,
                key: ProtectedResourceValueRule(
                    source: .constant,
                    value: "12345678901234567890123456789012",
                    encoding: .utf8
                )
            )
        )

        await #expect(throws: RuleExecutionError.self) {
            _ = try await runtime.load(
                ProtectedResourceLoadInput(
                    rule: rule,
                    sourceID: "example",
                    parameters: ["imageId": "123"]
                )
            )
        }
    }

    @Test func loaderDecodesUTF8Base64ImageOutput() async throws {
        let key: Data = Data("12345678901234567890123456789012".utf8)
        let iv: Data = Data("abcdefghijklmnop".utf8)
        let plaintextImage: Data = Data([0x89, 0x50, 0x4E, 0x47]) + Data("decoded-image".utf8)
        let plaintext: Data = Data("data:image/png;base64,\(plaintextImage.base64EncodedString())".utf8)
        let ciphertext: Data = try Self.crypt(
            operation: CCOperation(kCCEncrypt),
            input: plaintext,
            key: key,
            iv: iv
        )
        let loader: RecordingProtectedResourceDataLoader = RecordingProtectedResourceDataLoader(
            responses: [
                "https://api.example.test/binary/123": ciphertext
            ]
        )
        let runtime: ProtectedResourceLoader = ProtectedResourceLoader(
            dataLoader: loader,
            decryptor: CommonCryptoProtectedResourceDecryptor()
        )
        let rule: ProtectedResourceRule = ProtectedResourceRule(
            type: .encryptedBinary,
            binaryRequest: ProtectedResourceRequestRule(url: "https://api.example.test/binary/{imageId}"),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .cbc,
                padding: .pkcs7,
                key: ProtectedResourceValueRule(
                    source: .constant,
                    value: String(decoding: key, as: UTF8.self),
                    encoding: .utf8
                ),
                iv: ProtectedResourceValueRule(
                    source: .constant,
                    value: String(decoding: iv, as: UTF8.self),
                    encoding: .utf8
                ),
                ciphertextEncoding: .raw
            ),
            output: ProtectedResourceOutputRule(format: "base64Image", contentType: .image)
        )

        let output: ProtectedResourceOutput = try await runtime.load(
            ProtectedResourceLoadInput(
                rule: rule,
                sourceID: "example",
                parameters: ["imageId": "123"]
            )
        )

        #expect(output.contentType == .image)
        #expect(output.data == plaintextImage)
    }

    @Test func loaderRetriesTransientGatewayKeyResponse() async throws {
        let key: Data = Data("12345678901234567890123456789012".utf8)
        let iv: Data = Data("abcdefghijklmnop".utf8)
        let plaintext: Data = Data([0x89, 0x50, 0x4E, 0x47]) + Data("decoded-image".utf8)
        let ciphertext: Data = try Self.crypt(
            operation: CCOperation(kCCEncrypt),
            input: plaintext,
            key: key,
            iv: iv
        )
        let loader: RecordingProtectedResourceDataLoader = RecordingProtectedResourceDataLoader(
            responseQueues: [
                "https://api.example.test/key/123": [
                    Data("<html><head><title>502 Bad Gateway</title></head></html>".utf8),
                    Data(
                        """
                        {"data":{"key":"\(key.base64EncodedString())","iv":"\(iv.base64EncodedString())"}}
                        """.utf8
                    )
                ],
                "https://api.example.test/binary/123/high": [ciphertext]
            ]
        )
        let runtime: ProtectedResourceLoader = ProtectedResourceLoader(
            dataLoader: loader,
            decryptor: CommonCryptoProtectedResourceDecryptor()
        )
        let rule: ProtectedResourceRule = ProtectedResourceRule(
            type: .encryptedBinary,
            keyRequest: ProtectedResourceRequestRule(url: "https://api.example.test/key/{imageId}"),
            keyPath: "data.key",
            binaryRequest: ProtectedResourceRequestRule(url: "https://api.example.test/binary/{imageId}/{quality}"),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .cbc,
                padding: .pkcs7,
                key: ProtectedResourceValueRule(source: .keyResponse, encoding: .base64),
                iv: ProtectedResourceValueRule(source: .keyResponse, path: "data.iv", encoding: .base64),
                ciphertextEncoding: .raw
            ),
            output: ProtectedResourceOutputRule(contentType: .image)
        )

        let output: ProtectedResourceOutput = try await runtime.load(
            ProtectedResourceLoadInput(
                rule: rule,
                sourceID: "example",
                parameters: [
                    "imageId": "123",
                    "quality": "high"
                ]
            )
        )

        #expect(output.data == plaintext)
        #expect(loader.requests.map(\.url.absoluteString) == [
            "https://api.example.test/key/123",
            "https://api.example.test/key/123",
            "https://api.example.test/binary/123/high"
        ])
    }

    @Test func requestTemplatesResolveArbitraryContextValues() async throws {
        let key: Data = Data("12345678901234567890123456789012".utf8)
        let iv: Data = Data("abcdefghijklmnop".utf8)
        let plaintext: Data = Data([0x89, 0x50, 0x4E, 0x47])
        let ciphertext: Data = try Self.crypt(
            operation: CCOperation(kCCEncrypt),
            input: plaintext,
            key: key,
            iv: iv
        )
        let loader: RecordingProtectedResourceDataLoader = RecordingProtectedResourceDataLoader(
            responses: [
                "https://api.example.test/key/123": Data(
                    """
                    {"data":{"key":"\(key.base64EncodedString())","iv":"\(iv.base64EncodedString())"}}
                    """.utf8
                ),
                "https://api.example.test/binary/123": ciphertext
            ]
        )
        let runtime: ProtectedResourceLoader = ProtectedResourceLoader(
            dataLoader: loader,
            decryptor: CommonCryptoProtectedResourceDecryptor()
        )
        let rule: ProtectedResourceRule = ProtectedResourceRule(
            type: .encryptedBinary,
            keyRequest: ProtectedResourceRequestRule(
                url: "https://api.example.test/key/{context.imageId}",
                request: RequestConfig(headers: ["uuid": "{context.uuid}"])
            ),
            keyPath: "data.key",
            binaryRequest: ProtectedResourceRequestRule(url: "https://api.example.test/binary/{imageId}"),
            decrypt: ProtectedResourceDecryptRule(
                algorithm: .aes,
                mode: .cbc,
                padding: .pkcs7,
                key: ProtectedResourceValueRule(source: .keyResponse, encoding: .base64),
                iv: ProtectedResourceValueRule(source: .keyResponse, path: "data.iv", encoding: .base64),
                ciphertextEncoding: .raw
            ),
            output: ProtectedResourceOutputRule(contentType: .image)
        )

        _ = try await runtime.load(
            ProtectedResourceLoadInput(
                rule: rule,
                sourceID: "example",
                parameters: ["imageId": "123"],
                context: SourceRequestContext(
                    sourceID: "example",
                    baseURL: nil,
                    purpose: .image,
                    contextValues: [
                        "imageId": "123",
                        "uuid": "rule-uuid"
                    ]
                )
            )
        )

        #expect(loader.requests.first?.url.absoluteString == "https://api.example.test/key/123")
        #expect(loader.requests.first?.request?.headers?["uuid"] == "rule-uuid")
    }

    private static func crypt(
        operation: CCOperation,
        input: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        let outputCapacity: Int = input.count + kCCBlockSizeAES128
        var output: Data = Data(count: outputCapacity)
        var outputLength: size_t = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        #expect(status == kCCSuccess)
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}

private final class RecordingProtectedResourceDataLoader: PageDataLoader {
    struct RecordedRequest {
        let url: URL
        let request: RequestConfig?
        let context: SourceRequestContext?
    }

    private let responses: [String: Data]
    private var responseQueues: [String: [Data]]
    private(set) var requests: [RecordedRequest] = []

    init(responses: [String: Data]) {
        self.responses = responses
        self.responseQueues = [:]
    }

    init(responseQueues: [String: [Data]]) {
        self.responses = [:]
        self.responseQueues = responseQueues
    }

    func loadData(_ request: PageLoadRequest) async throws -> PageDataResponse {
        self.requests.append(
            RecordedRequest(
                url: request.url,
                request: request.requestConfig,
                context: request.sourceContext
            )
        )

        if var queue: [Data] = self.responseQueues[request.url.absoluteString],
           queue.isEmpty == false {
            let data: Data = queue.removeFirst()
            self.responseQueues[request.url.absoluteString] = queue
            return PageDataResponse(data: data, finalURL: request.url)
        }

        guard let data: Data = self.responses[request.url.absoluteString] else {
            throw URLError(.fileDoesNotExist)
        }
        return PageDataResponse(data: data, finalURL: request.url)
    }
}
