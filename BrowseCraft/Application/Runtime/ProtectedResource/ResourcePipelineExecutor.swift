import Foundation
import BrowseCraftCore

// 中文注释：ResourcePipelineExecutor 只负责解释 Core 中的 pipeline 合同；网络和密码学能力均由协议注入。

struct ResourcePipelineExecutionOutput {
    let data: Data
    let contentType: ResourcePipelineContentType
}

indirect enum ResourcePipelineInputValue: Hashable {
    case string(String)
    case data(Data)
    case number(Double)
    case boolean(Bool)
    case object([String: ResourcePipelineInputValue])
    case array([ResourcePipelineInputValue])
    case null
}

struct ResourcePipelineExecutionInput {
    let rule: ResourcePipelineRule
    let sourceID: String
    let item: [String: ResourcePipelineInputValue]
    let root: [String: ResourcePipelineInputValue]
    let context: [String: ResourcePipelineInputValue]
    let requestContext: SourceRequestContext?

    init(
        rule: ResourcePipelineRule,
        sourceID: String,
        item: [String: ResourcePipelineInputValue] = [:],
        root: [String: ResourcePipelineInputValue] = [:],
        context: [String: ResourcePipelineInputValue] = [:],
        requestContext: SourceRequestContext? = nil
    ) {
        self.rule = rule
        self.sourceID = sourceID
        self.item = item
        self.root = root
        self.context = context
        self.requestContext = requestContext
    }
}

protocol ResourcePipelineCryptography {
    func hash(_ data: Data, algorithm: ResourceHashAlgorithm) throws -> Data

    func decrypt(
        _ ciphertext: Data,
        algorithm: ResourceCipherAlgorithm,
        mode: ResourceCipherMode,
        padding: ResourceCipherPadding,
        key: Data,
        iv: Data
    ) throws -> Data
}

enum ResourcePipelineExecutorError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidBinding(name: String, reason: String)
    case invalidStep(id: String, reason: String)
    case duplicateStepID(String)
    case ambiguousName(String)
    case missingReference(source: ResourceValueReferenceSource, name: String)
    case unresolvedTemplateToken(String)
    case invalidURL(String)
    case requestFailed(url: String, reason: String)
    case invalidJSON(stepID: String)
    case missingPath(String)
    case incompatibleValue(expected: String)
    case invalidEncoding(ResourceDataEncoding)
    case invalidSlice(offset: Int, length: Int)
    case invalidSplit(expected: Int, actual: Int)
    case cryptographyFailed(stepID: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported resource pipeline version: \(version)"
        case .invalidBinding(let name, let reason):
            return "Invalid resource pipeline binding: name=\(name) reason=\(reason)"
        case .invalidStep(let id, let reason):
            return "Invalid resource pipeline step: id=\(id) reason=\(reason)"
        case .duplicateStepID(let id):
            return "Duplicate resource pipeline step id: \(id)"
        case .ambiguousName(let name):
            return "Resource pipeline name collides with a binding: \(name)"
        case .missingReference(let source, let name):
            return "Missing resource pipeline reference: source=\(source.rawValue) name=\(name)"
        case .unresolvedTemplateToken(let token):
            return "Unresolved resource pipeline template token: \(token)"
        case .invalidURL(let value):
            return "Invalid resource pipeline URL: \(value)"
        case .requestFailed(let url, let reason):
            return "Resource pipeline request failed: url=\(url) reason=\(reason)"
        case .invalidJSON(let stepID):
            return "Invalid resource pipeline JSON response: step=\(stepID)"
        case .missingPath(let path):
            return "Missing resource pipeline value path: \(path)"
        case .incompatibleValue(let expected):
            return "Incompatible resource pipeline value: expected=\(expected)"
        case .invalidEncoding(let encoding):
            return "Invalid resource pipeline encoding: \(encoding.rawValue)"
        case .invalidSlice(let offset, let length):
            return "Invalid resource pipeline slice: offset=\(offset) length=\(length)"
        case .invalidSplit(let expected, let actual):
            return "Invalid resource pipeline split: expected=\(expected) actual=\(actual)"
        case .cryptographyFailed(let stepID, let reason):
            return "Resource pipeline cryptography failed: step=\(stepID) reason=\(reason)"
        }
    }
}

struct ResourcePipelineExecutor {
    private let dataLoader: PageDataLoader
    private let cryptography: ResourcePipelineCryptography

    init(dataLoader: PageDataLoader, cryptography: ResourcePipelineCryptography) {
        self.dataLoader = dataLoader
        self.cryptography = cryptography
    }

    func execute(_ input: ResourcePipelineExecutionInput) async throws -> ResourcePipelineExecutionOutput {
        try self.validate(input.rule)

        let bindings: [String: ResourcePipelineRuntimeValue] = try self.resolveBindings(input)
        var stepValues: [String: ResourcePipelineRuntimeValue] = [:]

        for step: ResourcePipelineStepRule in input.rule.steps {
            let value: ResourcePipelineRuntimeValue = try await self.execute(
                step,
                input: input,
                bindings: bindings,
                stepValues: stepValues
            )
            stepValues[step.id] = value
        }

        let outputValue: ResourcePipelineRuntimeValue = try self.resolve(
            input.rule.output.value,
            bindings: bindings,
            stepValues: stepValues
        )
        return ResourcePipelineExecutionOutput(
            data: try outputValue.dataValue(),
            contentType: input.rule.output.contentType
        )
    }

    private func validate(_ rule: ResourcePipelineRule) throws {
        guard rule.version == 2 else {
            throw ResourcePipelineExecutorError.unsupportedVersion(rule.version)
        }

        for (name, binding): (String, ResourceBindingRule) in rule.bindings {
            guard name.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidBinding(name: name, reason: "empty name")
            }
            switch binding.source {
            case .constant:
                guard binding.value != nil else {
                    throw ResourcePipelineExecutorError.invalidBinding(name: name, reason: "missing value")
                }
            case .item, .root, .context:
                guard let path: String = binding.path,
                      path.isEmpty == false else {
                    throw ResourcePipelineExecutorError.invalidBinding(name: name, reason: "missing path")
                }
            }
        }

        let bindingNames: Set<String> = Set(rule.bindings.keys)
        var availableSteps: Set<String> = []
        for step: ResourcePipelineStepRule in rule.steps {
            guard step.id.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidStep(id: step.id, reason: "empty id")
            }
            guard availableSteps.contains(step.id) == false else {
                throw ResourcePipelineExecutorError.duplicateStepID(step.id)
            }
            guard bindingNames.contains(step.id) == false else {
                throw ResourcePipelineExecutorError.ambiguousName(step.id)
            }

            try self.validate(
                step.operation,
                stepID: step.id,
                bindingNames: bindingNames,
                availableSteps: availableSteps
            )
            for reference: ResourceValueReferenceRule in self.references(in: step.operation) {
                try self.validate(
                    reference,
                    bindingNames: bindingNames,
                    availableSteps: availableSteps
                )
            }
            availableSteps.insert(step.id)
        }

        try self.validate(
            rule.output.value,
            bindingNames: bindingNames,
            availableSteps: availableSteps
        )
    }

    private func validate(
        _ operation: ResourcePipelineOperationRule,
        stepID: String,
        bindingNames: Set<String>,
        availableSteps: Set<String>
    ) throws {
        switch operation {
        case .request(let rule):
            guard rule.urlTemplate.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "empty URL template")
            }
            for token: String in ResourcePipelineTemplateResolver.tokens(in: rule) {
                if token.hasPrefix("binding.") {
                    let name: String = String(token.dropFirst("binding.".count))
                    guard bindingNames.contains(name) else {
                        throw ResourcePipelineExecutorError.unresolvedTemplateToken(token)
                    }
                    continue
                }
                if token.hasPrefix("step.") {
                    let stepPath: String = String(token.dropFirst("step.".count))
                    let name: String = stepPath.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
                    guard availableSteps.contains(name) else {
                        throw ResourcePipelineExecutorError.unresolvedTemplateToken(token)
                    }
                    continue
                }
                throw ResourcePipelineExecutorError.unresolvedTemplateToken(token)
            }
        case .extract(let rule):
            guard rule.path.isEmpty == false else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "empty extract path")
            }
        case .slice(let rule):
            guard rule.offset >= 0,
                  rule.length >= 0 else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "negative slice")
            }
        case .split(let rule):
            guard rule.delimiter.isEmpty == false,
                  rule.fields.isEmpty == false,
                  Set(rule.fields).count == rule.fields.count,
                  rule.fields.allSatisfy({ $0.isEmpty == false }) else {
                throw ResourcePipelineExecutorError.invalidStep(id: stepID, reason: "invalid split declaration")
            }
        case .decode, .hash, .decrypt:
            break
        }
    }

    private func validate(
        _ reference: ResourceValueReferenceRule,
        bindingNames: Set<String>,
        availableSteps: Set<String>
    ) throws {
        switch reference.source {
        case .binding:
            guard bindingNames.contains(reference.name) else {
                throw ResourcePipelineExecutorError.missingReference(source: .binding, name: reference.name)
            }
        case .step:
            guard availableSteps.contains(reference.name) else {
                throw ResourcePipelineExecutorError.missingReference(source: .step, name: reference.name)
            }
        }
    }

    private func references(in operation: ResourcePipelineOperationRule) -> [ResourceValueReferenceRule] {
        switch operation {
        case .request:
            return []
        case .extract(let rule):
            return [rule.input]
        case .decode(let rule):
            return [rule.input]
        case .hash(let rule):
            return [rule.input]
        case .slice(let rule):
            return [rule.input]
        case .split(let rule):
            return [rule.input]
        case .decrypt(let rule):
            return [rule.input, rule.key, rule.iv]
        }
    }

    private func resolveBindings(
        _ input: ResourcePipelineExecutionInput
    ) throws -> [String: ResourcePipelineRuntimeValue] {
        let itemValue: ResourcePipelineInputValue = .object(input.item)
        let rootValue: ResourcePipelineInputValue = .object(input.root)
        var contextValues: [String: ResourcePipelineInputValue] = input.context
        input.requestContext?.contextValues.forEach { key, value in
            contextValues[key] = .string(value)
        }
        let contextValue: ResourcePipelineInputValue = .object(contextValues)

        return try input.rule.bindings.reduce(into: [:]) { result, entry in
            let name: String = entry.key
            let binding: ResourceBindingRule = entry.value
            switch binding.source {
            case .constant:
                result[name] = .string(binding.value ?? "")
            case .item:
                result[name] = try itemValue.runtimeValue(at: binding.path ?? "")
            case .root:
                result[name] = try rootValue.runtimeValue(at: binding.path ?? "")
            case .context:
                result[name] = try contextValue.runtimeValue(at: binding.path ?? "")
            }
        }
    }

    private func execute(
        _ step: ResourcePipelineStepRule,
        input: ResourcePipelineExecutionInput,
        bindings: [String: ResourcePipelineRuntimeValue],
        stepValues: [String: ResourcePipelineRuntimeValue]
    ) async throws -> ResourcePipelineRuntimeValue {
        switch step.operation {
        case .request(let rule):
            return try await self.executeRequest(
                rule,
                stepID: step.id,
                input: input,
                bindings: bindings,
                stepValues: stepValues
            )
        case .extract(let rule):
            let inputValue: ResourcePipelineRuntimeValue = try self.resolve(
                rule.input,
                bindings: bindings,
                stepValues: stepValues
            )
            let extracted: ResourcePipelineRuntimeValue = try inputValue.value(at: rule.path)
            switch rule.outputType {
            case .json:
                return extracted
            case .string:
                return .string(try extracted.stringValue())
            }
        case .decode(let rule):
            let inputValue: ResourcePipelineRuntimeValue = try self.resolve(
                rule.input,
                bindings: bindings,
                stepValues: stepValues
            )
            return try ResourcePipelineCodec.decode(inputValue, encoding: rule.encoding)
        case .hash(let rule):
            let inputValue: ResourcePipelineRuntimeValue = try self.resolve(
                rule.input,
                bindings: bindings,
                stepValues: stepValues
            )
            do {
                let digest: Data = try self.cryptography.hash(
                    try inputValue.dataValue(),
                    algorithm: rule.algorithm
                )
                return try ResourcePipelineCodec.encodeHash(digest, encoding: rule.outputEncoding)
            } catch let error as ResourcePipelineExecutorError {
                throw error
            } catch {
                throw ResourcePipelineExecutorError.cryptographyFailed(
                    stepID: step.id,
                    reason: error.localizedDescription
                )
            }
        case .slice(let rule):
            let inputValue: ResourcePipelineRuntimeValue = try self.resolve(
                rule.input,
                bindings: bindings,
                stepValues: stepValues
            )
            return try inputValue.slice(offset: rule.offset, length: rule.length, unit: rule.unit)
        case .split(let rule):
            let inputValue: ResourcePipelineRuntimeValue = try self.resolve(
                rule.input,
                bindings: bindings,
                stepValues: stepValues
            )
            let parts: [String] = try inputValue.stringValue().components(separatedBy: rule.delimiter)
                .filter { rule.omittingEmptySubsequences == false || $0.isEmpty == false }
            guard parts.count == rule.fields.count else {
                throw ResourcePipelineExecutorError.invalidSplit(
                    expected: rule.fields.count,
                    actual: parts.count
                )
            }
            return .fields(Dictionary(uniqueKeysWithValues: zip(rule.fields, parts).map { pair in
                (pair.0, .string(pair.1))
            }))
        case .decrypt(let rule):
            let ciphertext: Data = try self.resolve(
                rule.input,
                bindings: bindings,
                stepValues: stepValues
            ).dataValue()
            let key: Data = try self.resolve(
                rule.key,
                bindings: bindings,
                stepValues: stepValues
            ).dataValue()
            let iv: Data = try self.resolve(
                rule.iv,
                bindings: bindings,
                stepValues: stepValues
            ).dataValue()
            do {
                return .data(
                    try self.cryptography.decrypt(
                        ciphertext,
                        algorithm: rule.algorithm,
                        mode: rule.mode,
                        padding: rule.padding,
                        key: key,
                        iv: iv
                    )
                )
            } catch {
                throw ResourcePipelineExecutorError.cryptographyFailed(
                    stepID: step.id,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func executeRequest(
        _ rule: ResourceRequestOperationRule,
        stepID: String,
        input: ResourcePipelineExecutionInput,
        bindings: [String: ResourcePipelineRuntimeValue],
        stepValues: [String: ResourcePipelineRuntimeValue]
    ) async throws -> ResourcePipelineRuntimeValue {
        let templateValues: [String: String] = try self.templateValues(
            bindings: bindings,
            stepValues: stepValues
        )
        let urlString: String = try ResourcePipelineTemplateResolver.resolve(
            rule.urlTemplate,
            values: templateValues
        )
        guard let url: URL = URL(string: urlString),
              url.scheme != nil,
              url.host != nil else {
            throw ResourcePipelineExecutorError.invalidURL(urlString)
        }
        let request: RequestConfig? = try rule.request.map {
            try ResourcePipelineTemplateResolver.resolve($0, values: templateValues)
        }
        let context: SourceRequestContext = SourceRequestContext(
            sourceID: input.requestContext?.sourceID ?? input.sourceID,
            baseURL: input.requestContext?.baseURL,
            purpose: .protectedResource,
            refererURL: input.requestContext?.refererURL,
            additionalHeaders: input.requestContext?.additionalHeaders ?? [:],
            contextValues: input.requestContext?.contextValues ?? [:]
        )

        let data: Data
        do {
            data = try await self.dataLoader.getData(from: url, request: request, context: context)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ResourcePipelineExecutorError.requestFailed(
                url: url.absoluteString,
                reason: error.localizedDescription
            )
        }

        switch rule.responseType {
        case .data:
            return .data(data)
        case .text:
            guard let text: String = String(data: data, encoding: .utf8) else {
                throw ResourcePipelineExecutorError.incompatibleValue(expected: "UTF-8 text")
            }
            return .string(text)
        case .json:
            guard let object: Any = try? JSONSerialization.jsonObject(with: data) else {
                throw ResourcePipelineExecutorError.invalidJSON(stepID: stepID)
            }
            return .json(object)
        }
    }

    private func resolve(
        _ reference: ResourceValueReferenceRule,
        bindings: [String: ResourcePipelineRuntimeValue],
        stepValues: [String: ResourcePipelineRuntimeValue]
    ) throws -> ResourcePipelineRuntimeValue {
        let value: ResourcePipelineRuntimeValue?
        switch reference.source {
        case .binding:
            value = bindings[reference.name]
        case .step:
            value = stepValues[reference.name]
        }
        guard let value: ResourcePipelineRuntimeValue else {
            throw ResourcePipelineExecutorError.missingReference(
                source: reference.source,
                name: reference.name
            )
        }
        guard let path: String = reference.path,
              path.isEmpty == false else {
            return value
        }
        return try value.value(at: path)
    }

    private func templateValues(
        bindings: [String: ResourcePipelineRuntimeValue],
        stepValues: [String: ResourcePipelineRuntimeValue]
    ) throws -> [String: String] {
        var values: [String: String] = [:]
        for (name, value): (String, ResourcePipelineRuntimeValue) in bindings {
            if let scalar: String = try? value.stringValue() {
                values["binding.\(name)"] = scalar
            }
        }
        for (name, value): (String, ResourcePipelineRuntimeValue) in stepValues {
            if let scalar: String = try? value.stringValue() {
                values["step.\(name)"] = scalar
            }
            if case .fields(let fields) = value {
                for (field, fieldValue): (String, ResourcePipelineRuntimeValue) in fields {
                    values["step.\(name).\(field)"] = try fieldValue.stringValue()
                }
            }
        }
        return values
    }
}

private enum ResourcePipelineRuntimeValue {
    case data(Data)
    case string(String)
    case json(Any)
    case fields([String: ResourcePipelineRuntimeValue])

    func dataValue() throws -> Data {
        switch self {
        case .data(let data):
            return data
        case .string(let string):
            return Data(string.utf8)
        case .json(let object):
            if let string: String = ResourcePipelineJSONPath.scalarString(object) {
                return Data(string.utf8)
            }
            guard JSONSerialization.isValidJSONObject(object),
                  let data: Data = try? JSONSerialization.data(withJSONObject: object) else {
                throw ResourcePipelineExecutorError.incompatibleValue(expected: "data")
            }
            return data
        case .fields:
            throw ResourcePipelineExecutorError.incompatibleValue(expected: "data")
        }
    }

    func stringValue() throws -> String {
        switch self {
        case .data(let data):
            guard let value: String = String(data: data, encoding: .utf8) else {
                throw ResourcePipelineExecutorError.incompatibleValue(expected: "UTF-8 string")
            }
            return value
        case .string(let string):
            return string
        case .json(let object):
            guard let value: String = ResourcePipelineJSONPath.scalarString(object) else {
                throw ResourcePipelineExecutorError.incompatibleValue(expected: "scalar string")
            }
            return value
        case .fields:
            throw ResourcePipelineExecutorError.incompatibleValue(expected: "scalar string")
        }
    }

    func value(at path: String) throws -> ResourcePipelineRuntimeValue {
        switch self {
        case .json(let object):
            guard let value: Any = ResourcePipelineJSONPath.value(at: path, in: object) else {
                throw ResourcePipelineExecutorError.missingPath(path)
            }
            return .json(value)
        case .fields(let fields):
            var value: ResourcePipelineRuntimeValue = .fields(fields)
            for component: String in ResourcePipelineJSONPath.components(path) {
                guard case .fields(let currentFields) = value,
                      let nextValue: ResourcePipelineRuntimeValue = currentFields[component] else {
                    throw ResourcePipelineExecutorError.missingPath(path)
                }
                value = nextValue
            }
            return value
        case .data, .string:
            throw ResourcePipelineExecutorError.incompatibleValue(expected: "path-addressable value")
        }
    }

    func slice(
        offset: Int,
        length: Int,
        unit: ResourceSliceUnit
    ) throws -> ResourcePipelineRuntimeValue {
        switch unit {
        case .bytes:
            let data: Data = try self.dataValue()
            guard offset >= 0,
                  length >= 0,
                  offset + length <= data.count else {
                throw ResourcePipelineExecutorError.invalidSlice(offset: offset, length: length)
            }
            let start: Data.Index = data.index(data.startIndex, offsetBy: offset)
            let end: Data.Index = data.index(start, offsetBy: length)
            return .data(Data(data[start..<end]))
        case .characters:
            let characters: [Character] = Array(try self.stringValue())
            guard offset >= 0,
                  length >= 0,
                  offset + length <= characters.count else {
                throw ResourcePipelineExecutorError.invalidSlice(offset: offset, length: length)
            }
            return .string(String(characters[offset..<(offset + length)]))
        }
    }
}

private extension ResourcePipelineInputValue {
    func runtimeValue(at path: String) throws -> ResourcePipelineRuntimeValue {
        guard let value: ResourcePipelineInputValue = self.value(at: path) else {
            throw ResourcePipelineExecutorError.missingPath(path)
        }
        return value.runtimeValue
    }

    var runtimeValue: ResourcePipelineRuntimeValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .data(let value):
            return .data(value)
        case .number(let value):
            return .string(Self.scalarString(from: value))
        case .boolean(let value):
            return .string(value.description)
        case .object(let value):
            return .fields(value.mapValues(\.runtimeValue))
        case .array(let value):
            return .json(value.map(\.jsonObject))
        case .null:
            return .json(NSNull())
        }
    }

    /// 中文注释：JSON 数字在进入 URL/header 模板时，整数不应携带 Double 产生的 `.0` 后缀。
    private static func scalarString(from value: Double) -> String {
        if let integer: Int64 = Int64(exactly: value) {
            return String(integer)
        }
        return String(value)
    }

    var jsonObject: Any {
        switch self {
        case .string(let value):
            return value
        case .data(let value):
            return value.base64EncodedString()
        case .number(let value):
            return value
        case .boolean(let value):
            return value
        case .object(let value):
            return value.mapValues(\.jsonObject)
        case .array(let value):
            return value.map(\.jsonObject)
        case .null:
            return NSNull()
        }
    }

    func value(at path: String) -> ResourcePipelineInputValue? {
        let components: [String] = ResourcePipelineJSONPath.components(path)
        return components.reduce(self) { partial, component in
            guard let partial: ResourcePipelineInputValue else {
                return nil
            }
            switch partial {
            case .object(let object):
                return object[component]
            case .array(let array):
                guard let index: Int = Int(component),
                      array.indices.contains(index) else {
                    return nil
                }
                return array[index]
            case .string, .data, .number, .boolean, .null:
                return nil
            }
        }
    }
}

private enum ResourcePipelineJSONPath {
    static func components(_ path: String) -> [String] {
        return path
            .replacingOccurrences(of: "[", with: ".")
            .replacingOccurrences(of: "]", with: "")
            .split(separator: ".", omittingEmptySubsequences: true)
            .map(String.init)
    }

    static func value(at path: String, in object: Any) -> Any? {
        return self.components(path).reduce(Optional(object)) { partial, component in
            guard let partial: Any else {
                return nil
            }
            if let dictionary: [String: Any] = partial as? [String: Any] {
                return dictionary[component]
            }
            if let array: [Any] = partial as? [Any],
               let index: Int = Int(component),
               array.indices.contains(index) {
                return array[index]
            }
            return nil
        }
    }

    static func scalarString(_ object: Any) -> String? {
        switch object {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        case is NSNull:
            return nil
        default:
            return nil
        }
    }
}

private enum ResourcePipelineCodec {
    static func decode(
        _ value: ResourcePipelineRuntimeValue,
        encoding: ResourceDataEncoding
    ) throws -> ResourcePipelineRuntimeValue {
        switch encoding {
        case .raw:
            return .data(try value.dataValue())
        case .utf8:
            return .string(try value.stringValue())
        case .base64:
            return .data(try self.base64Data(from: value, urlSafe: false, dataURL: false))
        case .base64URL:
            return .data(try self.base64Data(from: value, urlSafe: true, dataURL: false))
        case .hex:
            return .data(try self.hexData(from: value.stringValue()))
        case .dataURLBase64:
            return .data(try self.base64Data(from: value, urlSafe: true, dataURL: true))
        }
    }

    static func encodeHash(
        _ data: Data,
        encoding: ResourceDataEncoding
    ) throws -> ResourcePipelineRuntimeValue {
        switch encoding {
        case .raw:
            return .data(data)
        case .hex:
            return .string(data.map { String(format: "%02x", $0) }.joined())
        case .base64:
            return .string(data.base64EncodedString())
        case .base64URL:
            return .string(
                data.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            )
        case .utf8, .dataURLBase64:
            throw ResourcePipelineExecutorError.invalidEncoding(encoding)
        }
    }

    private static func base64Data(
        from value: ResourcePipelineRuntimeValue,
        urlSafe: Bool,
        dataURL: Bool
    ) throws -> Data {
        var string: String = try value.stringValue().trimmingCharacters(in: .whitespacesAndNewlines)
        if dataURL,
           let commaIndex: String.Index = string.firstIndex(of: ","),
           string[..<commaIndex].lowercased().contains(";base64") {
            string = String(string[string.index(after: commaIndex)...])
        }
        string = string.filter { $0.isWhitespace == false }
        if urlSafe {
            string = string
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
        }
        let paddingCount: Int = (4 - string.count % 4) % 4
        string += String(repeating: "=", count: paddingCount)
        guard let data: Data = Data(base64Encoded: string) else {
            throw ResourcePipelineExecutorError.invalidEncoding(dataURL ? .dataURLBase64 : (urlSafe ? .base64URL : .base64))
        }
        return data
    }

    private static func hexData(from string: String) throws -> Data {
        let value: String = string.filter { $0.isWhitespace == false }
        guard value.count.isMultiple(of: 2) else {
            throw ResourcePipelineExecutorError.invalidEncoding(.hex)
        }
        var data: Data = Data()
        var index: String.Index = value.startIndex
        while index < value.endIndex {
            let end: String.Index = value.index(index, offsetBy: 2)
            guard let byte: UInt8 = UInt8(value[index..<end], radix: 16) else {
                throw ResourcePipelineExecutorError.invalidEncoding(.hex)
            }
            data.append(byte)
            index = end
        }
        return data
    }
}

private enum ResourcePipelineTemplateResolver {
    static func tokens(in rule: ResourceRequestOperationRule) -> Set<String> {
        var templates: [String] = [rule.urlTemplate]
        if let request: RequestConfig = rule.request {
            templates.append(contentsOf: request.headers?.values ?? Dictionary<String, String>().values)
            templates.append(contentsOf: request.imageHeaders?.values ?? Dictionary<String, String>().values)
            if let body: RequestBody = request.body {
                templates.append(body.value)
            }
            templates.append(contentsOf: request.imageRequest?.headers?.values ?? Dictionary<String, String>().values)
        }
        return Set(templates.flatMap(self.tokens(in:)))
    }

    private static func tokens(in template: String) -> [String] {
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: #"\{([^{}]+)\}"#) else {
            return []
        }
        return regex.matches(
            in: template,
            range: NSRange(template.startIndex..<template.endIndex, in: template)
        ).compactMap { match in
            guard let range: Range<String.Index> = Range(match.range(at: 1), in: template) else {
                return nil
            }
            return String(template[range])
        }
    }

    static func resolve(_ template: String, values: [String: String]) throws -> String {
        let regex: NSRegularExpression = try NSRegularExpression(pattern: #"\{([^{}]+)\}"#)
        var output: String = template
        let matches: [NSTextCheckingResult] = regex.matches(
            in: template,
            range: NSRange(template.startIndex..<template.endIndex, in: template)
        )
        for match: NSTextCheckingResult in matches.reversed() {
            guard let tokenRange: Range<String.Index> = Range(match.range(at: 1), in: template),
                  let fullRange: Range<String.Index> = Range(match.range(at: 0), in: output) else {
                continue
            }
            let token: String = String(template[tokenRange])
            guard let value: String = values[token] else {
                throw ResourcePipelineExecutorError.unresolvedTemplateToken(token)
            }
            output.replaceSubrange(fullRange, with: value)
        }
        return output
    }

    static func resolve(_ request: RequestConfig, values: [String: String]) throws -> RequestConfig {
        var result: RequestConfig = request
        result.headers = try request.headers?.mapValues { try self.resolve($0, values: values) }
        result.imageHeaders = try request.imageHeaders?.mapValues { try self.resolve($0, values: values) }
        if let body: RequestBody = request.body {
            result.body = RequestBody(
                contentType: body.contentType,
                value: try self.resolve(body.value, values: values)
            )
        }
        if var imageRequest: ImageRequestConfig = request.imageRequest {
            imageRequest.headers = try imageRequest.headers?.mapValues { try self.resolve($0, values: values) }
            result.imageRequest = imageRequest
        }
        return result
    }
}
