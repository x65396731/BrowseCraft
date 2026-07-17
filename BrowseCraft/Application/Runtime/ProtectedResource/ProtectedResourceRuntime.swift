import CommonCrypto
import Foundation
import BrowseCraftCore

// 中文注释：ProtectedResourceRuntime.swift 实现受保护资源的请求编排和白名单解密，不接具体 reader UI。

struct ProtectedResourceOutput {
    let data: Data
    let contentType: ProtectedResourceOutputContentType
}

struct ProtectedResourceLoadInput {
    let rule: ProtectedResourceRule
    let sourceID: String
    let parameters: [String: String]
    let context: SourceRequestContext?

    init(
        rule: ProtectedResourceRule,
        sourceID: String,
        parameters: [String: String] = [:],
        context: SourceRequestContext? = nil
    ) {
        self.rule = rule
        self.sourceID = sourceID
        self.parameters = parameters
        self.context = context
    }
}

enum ProtectedResourceRuntimeError: LocalizedError, Equatable {
    case invalidURL(String)
    case requestFailed(url: String, reason: String)
    case invalidKeyResponse(reason: String)
    case missingValue(source: ProtectedResourceValueSource, path: String?)
    case unsupportedDecryptConfiguration(reason: String)
    case invalidEncodedValue(encoding: ProtectedResourceDataEncoding)
    case decryptFailed(reason: String)
    case invalidKeyDerivation(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid protected resource URL: \(url)"
        case .requestFailed(let url, let reason):
            return "Protected resource request failed: url=\(url) reason=\(reason)"
        case .invalidKeyResponse(let reason):
            return "Invalid key response: \(reason)"
        case .missingValue(let source, let path):
            return "Missing protected resource value: source=\(source.rawValue) path=\(path ?? "nil")"
        case .unsupportedDecryptConfiguration(let reason):
            return "Unsupported decrypt configuration: \(reason)"
        case .invalidEncodedValue(let encoding):
            return "Invalid encoded value: encoding=\(encoding.rawValue)"
        case .decryptFailed(let reason):
            return "Decrypt failed: \(reason)"
        case .invalidKeyDerivation(let reason):
            return "Invalid key derivation: \(reason)"
        }
    }
}

private enum ProtectedResourceOutputFormat {
    static let raw: Set<String> = ["", "raw", "binary"]
    static let base64Image: Set<String> = [
        "base64",
        "base64image",
        "base64url",
        "dataurl",
        "dataurlimage",
        "utf8base64",
        "utf8base64image"
    ]
}

private actor ProtectedResourceRequestLimiter {
    private let limit: Int
    private var inFlight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if self.inFlight < self.limit {
            self.inFlight += 1
            return
        }

        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func release() {
        if self.waiters.isEmpty {
            self.inFlight = max(0, self.inFlight - 1)
            return
        }

        let continuation: CheckedContinuation<Void, Never> = self.waiters.removeFirst()
        continuation.resume()
    }
}

protocol ProtectedResourceDecrypting {
    func decrypt(ciphertext: Data, rule: ProtectedResourceDecryptRule, key: Data, iv: Data?) throws -> Data
}

struct CommonCryptoProtectedResourceDecryptor: ProtectedResourceDecrypting {
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

struct ProtectedResourceLoader {
    private static let keyRequestLimiter: ProtectedResourceRequestLimiter = ProtectedResourceRequestLimiter(limit: 4)

    private let dataLoader: PageDataLoader
    private let decryptor: ProtectedResourceDecrypting

    init(
        dataLoader: PageDataLoader,
        decryptor: ProtectedResourceDecrypting = CommonCryptoProtectedResourceDecryptor()
    ) {
        self.dataLoader = dataLoader
        self.decryptor = decryptor
    }

    func load(_ input: ProtectedResourceLoadInput) async throws -> ProtectedResourceOutput {
        do {
            return try await self.loadProtectedResource(input)
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw RuleExecutionError.protectedResource(
                stage: .image,
                sourceID: input.sourceID,
                reason: error.localizedDescription
            )
        }
    }

    private func loadProtectedResource(_ input: ProtectedResourceLoadInput) async throws -> ProtectedResourceOutput {
        guard input.rule.type == .encryptedBinary else {
            throw ProtectedResourceRuntimeError.unsupportedDecryptConfiguration(
                reason: "type=\(input.rule.type.rawValue)"
            )
        }

        let keyResponseObject: Any?
        if let keyRequest: ProtectedResourceRequestRule = input.rule.keyRequest {
            keyResponseObject = try await self.fetchJSON(
                requestRule: keyRequest,
                input: input,
                purpose: .protectedResource
            )
        } else {
            keyResponseObject = nil
        }

        let encryptedData: Data = try await self.fetch(
            requestRule: input.rule.binaryRequest,
            input: input,
            purpose: input.context?.purpose ?? .image
        )
        let ciphertext: Data = try ProtectedResourceValueResolver.data(
            from: encryptedData,
            encoding: input.rule.decrypt.ciphertextEncoding ?? .raw
        )
        let keyDerivationResult: [String: String]? = try input.rule.decrypt.keyDerivation.map { keyDerivationRule in
            try self.deriveKeyEnvelope(
                rule: keyDerivationRule,
                envelopePath: input.rule.keyPath,
                keyResponse: keyResponseObject,
                parameters: input.parameters,
                sourceID: input.sourceID,
                context: input.context
            )
        }
        let key: Data = try ProtectedResourceValueResolver.valueData(
            rule: self.decryptRuleKey(input.rule),
            keyResponse: keyResponseObject,
            parameters: input.parameters,
            context: input.context,
            keyDerivationResult: keyDerivationResult
        )
        let iv: Data? = try input.rule.decrypt.iv.map { ivRule in
            try ProtectedResourceValueResolver.valueData(
                rule: ivRule,
                keyResponse: keyResponseObject,
                parameters: input.parameters,
                context: input.context,
                keyDerivationResult: keyDerivationResult
            )
        }

        RuleExecutionLogger.log(
            stage: .image,
            event: "protected-resource-decrypt",
            fields: [
                "source": input.sourceID,
                "algorithm": input.rule.decrypt.algorithm.rawValue,
                "mode": input.rule.decrypt.mode.rawValue,
                "padding": input.rule.decrypt.padding?.rawValue ?? "nil",
                "hasKeyDerivation": (input.rule.decrypt.keyDerivation != nil).description,
                "keyLength": key.count,
                "ivLength": iv?.count ?? 0,
                "cipherBytes": ciphertext.count
            ]
        )

        let decryptedData: Data = try self.decryptor.decrypt(
            ciphertext: ciphertext,
            rule: input.rule.decrypt,
            key: key,
            iv: iv
        )
        let outputData: Data = try self.outputData(
            from: decryptedData,
            outputRule: input.rule.output
        )

        RuleExecutionLogger.log(
            stage: .image,
            event: "protected-resource-output",
            fields: [
                "source": input.sourceID,
                "contentType": input.rule.output?.contentType.rawValue ?? "binary",
                "format": input.rule.output?.format ?? "raw",
                "bytes": outputData.count,
                "shape": self.outputShape(outputData)
            ]
        )

        return ProtectedResourceOutput(
            data: outputData,
            contentType: input.rule.output?.contentType ?? .binary
        )
    }

    private func outputData(
        from decryptedData: Data,
        outputRule: ProtectedResourceOutputRule?
    ) throws -> Data {
        let format: String = (outputRule?.format ?? "raw").lowercased()
        if ProtectedResourceOutputFormat.raw.contains(format) {
            return decryptedData
        }

        if ProtectedResourceOutputFormat.base64Image.contains(format) {
            let encodedString: String = String(decoding: decryptedData, as: UTF8.self)
            guard let imageData: Data = Self.decodeBase64ImageData(encodedString) else {
                throw ProtectedResourceRuntimeError.invalidEncodedValue(encoding: .base64)
            }
            return imageData
        }

        throw ProtectedResourceRuntimeError.unsupportedDecryptConfiguration(reason: "outputFormat=\(format)")
    }

    private static func decodeBase64ImageData(_ string: String) -> Data? {
        let trimmedString: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if let commaIndex: String.Index = trimmedString.firstIndex(of: ","),
           trimmedString[..<commaIndex].lowercased().contains(";base64") {
            payload = String(trimmedString[trimmedString.index(after: commaIndex)...])
        } else {
            payload = trimmedString
        }

        let compactPayload: String = payload
            .filter { character in
                character.isWhitespace == false
            }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let missingPadding: Int = (4 - compactPayload.count % 4) % 4
        let paddedPayload: String = compactPayload + String(repeating: "=", count: missingPadding)
        return Data(base64Encoded: paddedPayload)
    }

    private func outputShape(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpeg"
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }
        if data.count >= 12,
           data[0] == 0x52,
           data[1] == 0x49,
           data[2] == 0x46,
           data[3] == 0x46,
           data[8] == 0x57,
           data[9] == 0x45,
           data[10] == 0x42,
           data[11] == 0x50 {
            return "webp"
        }

        let prefix: String = String(decoding: data.prefix(32), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if prefix.hasPrefix("data:image/") {
            return "dataURL"
        }
        if Self.decodeBase64ImageData(String(decoding: data.prefix(256), as: UTF8.self)) != nil {
            return "base64Like"
        }
        return "unknown"
    }

    private func decryptRuleKey(_ rule: ProtectedResourceRule) -> ProtectedResourceValueRule {
        if rule.decrypt.key.source == .keyDerivationResult {
            return rule.decrypt.key
        }

        guard rule.decrypt.key.source == .keyResponse,
              rule.decrypt.key.path == nil,
              let keyPath: String = rule.keyPath else {
            return rule.decrypt.key
        }

        return ProtectedResourceValueRule(
            source: .keyResponse,
            path: keyPath,
            value: rule.decrypt.key.value,
            encoding: rule.decrypt.key.encoding
        )
    }

    private func deriveKeyEnvelope(
        rule: ProtectedResourceKeyDerivationRule,
        envelopePath: String?,
        keyResponse: Any?,
        parameters: [String: String],
        sourceID: String,
        context: SourceRequestContext?
    ) throws -> [String: String] {
        guard rule.type == "decryptKeyEnvelope" else {
            throw ProtectedResourceRuntimeError.invalidKeyDerivation(reason: "type=\(rule.type)")
        }
        guard let keyResponse: Any else {
            throw ProtectedResourceRuntimeError.invalidKeyResponse(reason: "missing key response")
        }
        guard let envelopePath: String,
              let encryptedEnvelope: String = ComicRuleAPIResolver.stringValue(
                ComicRuleAPIResolver.firstJSONValue(at: envelopePath, in: keyResponse)
              ),
              encryptedEnvelope.isEmpty == false else {
            throw ProtectedResourceRuntimeError.missingValue(source: .keyResponse, path: envelopePath)
        }

        let secret: String = try ProtectedResourceValueResolver.stringValue(
            rule: rule.contextSecret,
            keyResponse: keyResponse,
            parameters: parameters,
            context: context,
            keyDerivationResult: nil
        )
        let secretHashHex: String = try self.secretHashHex(secret, hash: rule.contextSecretDerivation.hash)
        let envelopeKeyHex: String = try self.hexSlice(rule.contextSecretDerivation.keyHex, from: secretHashHex)
        let envelopeIVHex: String = try self.hexSlice(rule.contextSecretDerivation.ivHex, from: secretHashHex)
        let envelopeKey: Data = try ProtectedResourceValueResolver.data(
            from: Data(envelopeKeyHex.utf8),
            encoding: rule.decrypt.keyEncoding ?? .hex
        )
        let envelopeIV: Data = try ProtectedResourceValueResolver.data(
            from: Data(envelopeIVHex.utf8),
            encoding: rule.decrypt.ivEncoding ?? .hex
        )
        let envelopeCiphertext: Data = try ProtectedResourceValueResolver.data(
            from: Data(encryptedEnvelope.utf8),
            encoding: rule.decrypt.inputEncoding ?? .base64
        )
        let envelopeDecryptRule: ProtectedResourceDecryptRule = ProtectedResourceDecryptRule(
            algorithm: rule.decrypt.algorithm,
            mode: rule.decrypt.mode,
            padding: rule.decrypt.padding,
            key: ProtectedResourceValueRule(source: .constant, value: envelopeKeyHex, encoding: .hex),
            iv: ProtectedResourceValueRule(source: .constant, value: envelopeIVHex, encoding: .hex),
            ciphertextEncoding: rule.decrypt.inputEncoding ?? .base64
        )

        RuleExecutionLogger.log(
            stage: .image,
            event: "protected-resource-key-derivation",
            fields: [
                "source": sourceID,
                "type": rule.type,
                "hash": rule.contextSecretDerivation.hash,
                "envelopeKeyLength": envelopeKey.count,
                "envelopeIVLength": envelopeIV.count,
                "envelopeCipherBytes": envelopeCiphertext.count
            ]
        )

        let envelopePlainData: Data = try self.decryptor.decrypt(
            ciphertext: envelopeCiphertext,
            rule: envelopeDecryptRule,
            key: envelopeKey,
            iv: envelopeIV
        )
        let envelopePlainText: String = String(decoding: envelopePlainData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [Substring] = envelopePlainText.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].isEmpty == false,
              parts[1].isEmpty == false else {
            throw ProtectedResourceRuntimeError.invalidKeyDerivation(reason: "unexpected result format")
        }

        return [
            "key": String(parts[0]),
            "iv": String(parts[1])
        ]
    }

    private func secretHashHex(_ secret: String, hash: String) throws -> String {
        guard hash.lowercased() == "sha512" else {
            throw ProtectedResourceRuntimeError.invalidKeyDerivation(reason: "hash=\(hash)")
        }

        let data: Data = Data(secret.utf8)
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            digest.withUnsafeMutableBufferPointer { digestBuffer in
                _ = CC_SHA512(bytes.baseAddress, CC_LONG(data.count), digestBuffer.baseAddress)
            }
        }
        return digest.map { byte in String(format: "%02x", byte) }.joined()
    }

    private func hexSlice(_ expression: String, from hex: String) throws -> String {
        let pattern: String = #"^(?:substr|substring)\((\d+),\s*(\d+)\)$"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern),
              let match: NSTextCheckingResult = regex.firstMatch(
                in: expression,
                range: NSRange(expression.startIndex..<expression.endIndex, in: expression)
              ),
              match.numberOfRanges == 3,
              let startRange: Range<String.Index> = Range(match.range(at: 1), in: expression),
              let lengthRange: Range<String.Index> = Range(match.range(at: 2), in: expression),
              let start: Int = Int(expression[startRange]),
              let length: Int = Int(expression[lengthRange]),
              start >= 0,
              length > 0,
              start + length <= hex.count else {
            throw ProtectedResourceRuntimeError.invalidKeyDerivation(reason: "slice=\(expression)")
        }

        let sliceStart: String.Index = hex.index(hex.startIndex, offsetBy: start)
        let sliceEnd: String.Index = hex.index(sliceStart, offsetBy: length)
        return String(hex[sliceStart..<sliceEnd])
    }

    private func fetch(
        requestRule: ProtectedResourceRequestRule,
        input: ProtectedResourceLoadInput,
        purpose: SourceRequestPurpose
    ) async throws -> Data {
        let urlString: String = ProtectedResourceTemplateResolver.replacingContext(
            in: ProtectedResourceTemplateResolver.replacingParameters(
                in: requestRule.url,
                parameters: input.parameters
            ),
            context: input.context
        )
        guard let url: URL = URL(string: urlString) else {
            throw ProtectedResourceRuntimeError.invalidURL(urlString)
        }

        let request: RequestConfig? = requestRule.request.map { request in
            ProtectedResourceTemplateResolver.request(
                request,
                parameters: input.parameters,
                context: input.context
            )
        }
        let requestContext: SourceRequestContext? = input.context.map { context in
            SourceRequestContext(
                sourceID: context.sourceID,
                baseURL: context.baseURL,
                purpose: purpose,
                refererURL: context.refererURL,
                additionalHeaders: context.additionalHeaders,
                contextValues: context.contextValues
            )
        }

        RuleExecutionLogger.log(
            stage: .image,
            event: "protected-resource-request",
            fields: [
                "source": input.sourceID,
                "purpose": purpose.rawValue,
                "url": url.absoluteString,
                "hasContext": (requestContext != nil).description,
                "requestScope": request?.scope?.rawValue ?? "nil",
                "requestMergePolicy": request?.mergePolicy?.rawValue ?? "nil",
                "headerCount": request?.headers?.count ?? 0,
                "headerNames": self.safeHeaderNames(request?.headers)
            ]
        )

        do {
            if let contextualDataLoader: ContextualPageDataLoader = self.dataLoader as? ContextualPageDataLoader {
                return try await contextualDataLoader.getData(
                    from: url,
                    request: request,
                    context: requestContext
                )
            }

            return try await self.dataLoader.getData(from: url, request: request)
        } catch {
            throw ProtectedResourceRuntimeError.requestFailed(
                url: url.absoluteString,
                reason: error.localizedDescription
            )
        }
    }

    private func fetchJSON(
        requestRule: ProtectedResourceRequestRule,
        input: ProtectedResourceLoadInput,
        purpose: SourceRequestPurpose
    ) async throws -> Any {
        await Self.keyRequestLimiter.acquire()
        do {
            let object: Any = try await self.fetchJSONWithRetry(
                requestRule: requestRule,
                input: input,
                purpose: purpose
            )
            await Self.keyRequestLimiter.release()
            return object
        } catch {
            await Self.keyRequestLimiter.release()
            throw error
        }
    }

    private func fetchJSONWithRetry(
        requestRule: ProtectedResourceRequestRule,
        input: ProtectedResourceLoadInput,
        purpose: SourceRequestPurpose
    ) async throws -> Any {
        let maxAttempts: Int = 3
        var lastError: Error?
        for attempt in 1...maxAttempts {
            let data: Data
            do {
                data = try await self.fetch(
                    requestRule: requestRule,
                    input: input,
                    purpose: purpose
                )
            } catch {
                lastError = error
                guard attempt < maxAttempts else {
                    throw error
                }
                self.logRetry(
                    sourceID: input.sourceID,
                    purpose: purpose,
                    attempt: attempt,
                    maxAttempts: maxAttempts,
                    reason: "requestError"
                )
                try await self.sleepBeforeRetry(attempt: attempt)
                continue
            }

            do {
                return try self.jsonObject(from: data)
            } catch {
                lastError = error
                guard attempt < maxAttempts,
                      self.isTransientGatewayResponse(data) else {
                    throw error
                }
                self.logRetry(
                    sourceID: input.sourceID,
                    purpose: purpose,
                    attempt: attempt,
                    maxAttempts: maxAttempts,
                    reason: self.responseShape(data)
                )
                try await self.sleepBeforeRetry(attempt: attempt)
            }
        }

        throw lastError ?? ProtectedResourceRuntimeError.invalidKeyResponse(reason: "unknown")
    }

    private func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProtectedResourceRuntimeError.invalidKeyResponse(
                reason: "\(error.localizedDescription) shape=\(self.responseShape(data))"
            )
        }
    }

    private func isTransientGatewayResponse(_ data: Data) -> Bool {
        let prefix: String = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        return prefix.contains("502 bad gateway")
            || prefix.contains("503 service unavailable")
            || prefix.contains("504 gateway timeout")
            || prefix.contains("<title>502")
            || prefix.contains("<title>503")
            || prefix.contains("<title>504")
    }

    private func responseShape(_ data: Data) -> String {
        let prefix: String = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if prefix.isEmpty {
            return "empty"
        }
        if prefix.hasPrefix("{") || prefix.hasPrefix("[") {
            return "jsonLike"
        }
        if prefix.contains("502 bad gateway") || prefix.contains("<title>502") {
            return "html502"
        }
        if prefix.contains("503 service unavailable") || prefix.contains("<title>503") {
            return "html503"
        }
        if prefix.contains("504 gateway timeout") || prefix.contains("<title>504") {
            return "html504"
        }
        if prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") {
            return "html"
        }
        return "nonJSON"
    }

    private func logRetry(
        sourceID: String,
        purpose: SourceRequestPurpose,
        attempt: Int,
        maxAttempts: Int,
        reason: String
    ) {
        RuleExecutionLogger.log(
            stage: .image,
            event: "protected-resource-retry",
            fields: [
                "source": sourceID,
                "purpose": purpose.rawValue,
                "attempt": attempt,
                "remaining": maxAttempts - attempt,
                "reason": reason
            ]
        )
    }

    private func sleepBeforeRetry(attempt: Int) async throws {
        let delay: UInt64 = UInt64(attempt) * 250_000_000
        try await Task.sleep(nanoseconds: delay)
    }

    private func safeHeaderNames(_ headers: [String: String]?) -> String {
        guard let headers: [String: String],
              headers.isEmpty == false else {
            return "none"
        }

        return headers.keys.sorted().joined(separator: ",")
    }
}

enum ProtectedResourceTemplateResolver {
    static func replacingParameters(in template: String, parameters: [String: String]) -> String {
        var output: String = template
        parameters.forEach { key, value in
            output = output.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return output
    }

    static func request(_ request: RequestConfig, parameters: [String: String], context: SourceRequestContext?) -> RequestConfig {
        var resolvedRequest: RequestConfig = request
        resolvedRequest.headers = request.headers?.mapValues { value in
            self.replacingContext(in: self.replacingParameters(in: value, parameters: parameters), context: context)
        }
        if let body: RequestBody = request.body {
            resolvedRequest.body = RequestBody(
                contentType: body.contentType,
                value: self.replacingContext(in: self.replacingParameters(in: body.value, parameters: parameters), context: context)
            )
        }
        return resolvedRequest
    }

    static func replacingContext(in template: String, context: SourceRequestContext?) -> String {
        var output: String = template
        let values: [String: String] = [
            "context.userAgent": self.contextValue(path: "userAgent", context: context)
                ?? BrowserRequestHeaders.Chrome.chromeUserAgent,
            "context.device": self.contextValue(path: "device", context: context) ?? "server",
            "context.deviceUUID": self.contextDeviceUUID(context: context),
            "context.readerAccessToken": self.contextValue(path: "readerAccessToken", context: context) ?? ""
        ]
        values.forEach { key, value in
            output = output.replacingOccurrences(of: "{\(key)}", with: value)
        }
        context?.contextValues.forEach { key, value in
            guard value.isEmpty == false else {
                return
            }
            output = output.replacingOccurrences(of: "{context.\(key)}", with: value)
        }
        return output
    }

    static func contextValue(path: String?, context: SourceRequestContext?) -> String? {
        if let path: String,
           let value: String = context?.contextValues[path],
           value.isEmpty == false {
            return value
        }

        switch path {
        case "userAgent":
            return BrowserRequestHeaders.Chrome.chromeUserAgent
        case "device":
            return "server"
        case "deviceUUID":
            return self.contextDeviceUUID(context: context)
        case "uuid":
            return context?.contextValues["uuid"] ?? context?.contextValues["deviceUUID"]
        case "readerAccessToken":
            return nil
        default:
            return nil
        }
    }

    private static func contextDeviceUUID(context: SourceRequestContext?) -> String {
        if let value: String = context?.contextValues["deviceUUID"] ?? context?.contextValues["uuid"],
           value.isEmpty == false {
            return value
        }

        let rawID: String = "BrowseCraft:\(context?.sourceID ?? "unknown"):\(context?.baseURL?.absoluteString ?? "unknown")"
        let data: Data? = rawID.data(using: .utf8)
        let encoded: String = data?.base64EncodedString() ?? rawID
        let sanitized: String = encoded
            .filter { character in
                character.isLetter || character.isNumber
            }
            .lowercased()
        let padded: String = sanitized.padding(toLength: 32, withPad: "0", startingAt: 0)
        return String(padded.prefix(32))
    }
}

enum ProtectedResourceValueResolver {
    static func valueData(
        rule: ProtectedResourceValueRule,
        keyResponse: Any?,
        parameters: [String: String],
        context: SourceRequestContext? = nil,
        keyDerivationResult: [String: String]? = nil
    ) throws -> Data {
        let rawValue: String = try self.stringValue(
            rule: rule,
            keyResponse: keyResponse,
            parameters: parameters,
            context: context,
            keyDerivationResult: keyDerivationResult
        )

        return try self.data(from: Data(rawValue.utf8), encoding: rule.encoding ?? .utf8)
    }

    static func stringValue(
        rule: ProtectedResourceValueRule,
        keyResponse: Any?,
        parameters: [String: String],
        context: SourceRequestContext? = nil,
        keyDerivationResult: [String: String]?
    ) throws -> String {
        let rawValue: String?
        switch rule.source {
        case .keyResponse:
            guard let keyResponse: Any else {
                throw ProtectedResourceRuntimeError.missingValue(source: rule.source, path: rule.path)
            }
            let path: String = rule.path ?? ""
            rawValue = ComicRuleAPIResolver.stringValue(
                ComicRuleAPIResolver.firstJSONValue(at: path, in: keyResponse)
            )
        case .parameter:
            rawValue = rule.path.flatMap { parameters[$0] } ?? rule.value.flatMap { parameters[$0] }
        case .context:
            rawValue = ProtectedResourceTemplateResolver.contextValue(path: rule.path ?? rule.value, context: context)
        case .constant:
            rawValue = rule.value
        case .keyDerivationResult:
            guard let keyDerivationResult: [String: String] else {
                throw ProtectedResourceRuntimeError.missingValue(source: rule.source, path: rule.path)
            }
            rawValue = rule.path.flatMap { keyDerivationResult[$0] } ?? rule.value.flatMap { keyDerivationResult[$0] }
        }

        guard let rawValue: String,
              rawValue.isEmpty == false else {
            throw ProtectedResourceRuntimeError.missingValue(source: rule.source, path: rule.path)
        }

        return rawValue
    }

    static func data(from data: Data, encoding: ProtectedResourceDataEncoding) throws -> Data {
        switch encoding {
        case .raw:
            return data
        case .utf8:
            return data
        case .base64:
            let string: String = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decodedData: Data = Data(base64Encoded: string) else {
                throw ProtectedResourceRuntimeError.invalidEncodedValue(encoding: encoding)
            }
            return decodedData
        case .hex:
            let string: String = String(decoding: data, as: UTF8.self)
            return try self.hexData(from: string)
        }
    }

    private static func hexData(from string: String) throws -> Data {
        let cleanedString: String = string
            .filter { character in
                character.isWhitespace == false
            }
        guard cleanedString.count.isMultiple(of: 2) else {
            throw ProtectedResourceRuntimeError.invalidEncodedValue(encoding: .hex)
        }

        var data: Data = Data()
        var index: String.Index = cleanedString.startIndex
        while index < cleanedString.endIndex {
            let nextIndex: String.Index = cleanedString.index(index, offsetBy: 2)
            let byteString: String = String(cleanedString[index..<nextIndex])
            guard let byte: UInt8 = UInt8(byteString, radix: 16) else {
                throw ProtectedResourceRuntimeError.invalidEncodedValue(encoding: .hex)
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
