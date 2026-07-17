import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：ProtectedResourceRule 模型测试，确认规则 JSON 可以表达 key API、加密二进制和 AES 参数。
struct ProtectedResourceRuleModelTests {
    @Test func readerImageAPIDecodesProtectedResourceRule() throws {
        let json: String = """
        {
          "url": "https://api.example.test/images?chapter={chapterId}",
          "itemPath": "data.images[]",
          "urlTemplate": "protected://{imageId}",
          "protectedResource": {
            "type": "encryptedBinary",
            "keyRequest": {
              "url": "https://api.example.test/book/chapter/image/{imageId}",
              "request": {
                "method": "GET",
                "headers": {
                  "device": "server"
                }
              }
            },
            "keyPath": "data.key",
            "binaryRequest": {
              "url": "https://api.example.test/fs/chapter_content/encrypt/{imageId}/{quality}"
            },
            "decrypt": {
              "algorithm": "AES",
              "mode": "CBC",
              "padding": "PKCS7",
              "key": {
                "source": "keyResponse",
                "encoding": "base64"
              },
              "iv": {
                "source": "keyResponse",
                "path": "data.iv",
                "encoding": "base64"
              },
              "ciphertextEncoding": "raw"
            },
            "output": {
              "contentType": "image"
            }
          }
        }
        """

        let rule: ReaderImageAPIRule = try JSONDecoder().decode(
            ReaderImageAPIRule.self,
            from: Data(json.utf8)
        )

        #expect(rule.protectedResource?.type == .encryptedBinary)
        #expect(rule.protectedResource?.keyPath == "data.key")
        #expect(rule.protectedResource?.decrypt.algorithm == .aes)
        #expect(rule.protectedResource?.decrypt.mode == .cbc)
        #expect(rule.protectedResource?.decrypt.key.encoding == .base64)
        #expect(rule.protectedResource?.output?.contentType == .image)
        #expect(rule.protectedResource?.keyRequest?.request?.headers?["device"] == "server")
    }

    @Test func galleryProtectedResourceFutureShapeDecodesForDiagnostics() throws {
        let json: String = """
        {
          "id": "reader",
          "imageItem": ".reader canvas",
          "imageUrl": "",
          "protectedResource": {
            "type": "image",
            "itemSource": {
              "url": "https://api.example.test/book/chapter/{chapterId}/info",
              "method": "GET",
              "headers": {
                "Accept": "application/json"
              },
              "itemPath": "data.chapter.proportion[]",
              "idPath": "id",
              "orderPath": "idx"
            },
            "decrypt": {
              "algorithm": "aes",
              "mode": "cbc",
              "keyDerivation": {
                "type": "decryptKeyEnvelope"
              }
            }
          }
        }
        """

        let rule: GalleryRule = try JSONDecoder().decode(
            GalleryRule.self,
            from: Data(json.utf8)
        )

        #expect(rule.protectedResource?.type == "image")
        #expect(rule.protectedResource?.itemSource?.itemPath == "data.chapter.proportion[]")
        #expect(rule.protectedResource?.itemSource?.idPath == "id")
        #expect(rule.protectedResource?.itemSource?.method == .get)
        #expect(rule.protectedResource?.nativeRule == nil)
        #expect(rule.protectedResource?.hasKeyDerivation == true)
    }

    @Test func galleryProtectedResourceWithKeyDerivationSynthesizesNativeRule() throws {
        let json: String = """
        {
          "id": "reader",
          "imageItem": ".reader canvas",
          "imageUrl": "",
          "protectedResource": {
            "type": "image",
            "itemSource": {
              "url": "https://api.example.test/book/chapter/{chapterId}/info",
              "method": "GET",
              "itemPath": "data.chapter.proportion[]",
              "idPath": "id"
            },
            "keyRequest": {
              "url": "https://api.example.test/book/chapter/image/{imageId}",
              "method": "GET",
              "headers": {
                "Accept": "application/json"
              },
              "keyEnvelope": {
                "source": "responseJSON",
                "path": "data.key",
                "encoding": "base64"
              }
            },
            "binaryRequest": {
              "url": "https://example.test/fs/chapter_content/encrypt/{imageId}/high",
              "method": "GET",
              "headers": {
                "Accept": "application/octet-stream,*/*"
              },
              "responseEncoding": "arrayBufferToBase64"
            },
            "decrypt": {
              "algorithm": "aes",
              "mode": "cbc",
              "padding": "pkcs7",
              "inputEncoding": "base64",
              "outputEncoding": "utf8Base64",
              "keyDerivation": {
                "type": "decryptKeyEnvelope",
                "contextSecret": {
                  "source": "constant",
                  "value": "freeforccc2020reading"
                },
                "contextSecretDerivation": {
                  "hash": "sha512",
                  "keyHex": "substr(0,64)",
                  "ivHex": "substr(30,32)"
                },
                "decrypt": {
                  "algorithm": "aes",
                  "mode": "cbc",
                  "padding": "pkcs7",
                  "inputEncoding": "base64",
                  "outputEncoding": "utf8",
                  "keyEncoding": "hex",
                  "ivEncoding": "hex"
                },
                "resultFormat": "colonSeparatedKeyIv"
              },
              "key": {
                "source": "keyDerivationResult",
                "path": "key",
                "encoding": "hex"
              },
              "iv": {
                "source": "keyDerivationResult",
                "path": "iv",
                "encoding": "hex"
              }
            },
            "output": {
              "format": "base64Image",
              "contentType": "auto"
            }
          }
        }
        """

        let rule: GalleryRule = try JSONDecoder().decode(
            GalleryRule.self,
            from: Data(json.utf8)
        )

        #expect(rule.protectedResource?.nativeRule?.type == .encryptedBinary)
        #expect(rule.protectedResource?.nativeRule?.keyPath == "data.key")
        #expect(rule.protectedResource?.nativeRule?.decrypt.keyDerivation?.type == "decryptKeyEnvelope")
        #expect(rule.protectedResource?.nativeRule?.decrypt.key.source == .keyDerivationResult)
        #expect(rule.protectedResource?.nativeRule?.decrypt.iv?.source == .keyDerivationResult)
        #expect(rule.protectedResource?.nativeRule?.output?.format == "base64Image")
        #expect(rule.protectedResource?.nativeRule?.output?.contentType == .image)
    }
}
