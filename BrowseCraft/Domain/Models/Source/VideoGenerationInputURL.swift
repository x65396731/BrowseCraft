import Foundation

struct VideoGenerationInputURL: Codable, Hashable, Sendable {
    let evaluatedURL: URL
    let submissionString: String

    init(evaluatedURL: URL, submissionString: String) {
        precondition(evaluatedURL.absoluteString == submissionString)
        self.evaluatedURL = evaluatedURL
        self.submissionString = submissionString
    }
}

enum VideoGenerationInputURLValidationError: Error, Equatable, Sendable {
    case empty
    case invalidURL
    case unsupportedScheme
    case userInfoNotAllowed
    case missingHost
}

struct VideoGenerationInputURLNormalizer: Sendable {
    func normalize(_ input: String) throws -> VideoGenerationInputURL {
        let trimmedInput: String = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.isEmpty == false else {
            throw VideoGenerationInputURLValidationError.empty
        }
        guard var components: URLComponents = URLComponents(string: trimmedInput) else {
            throw VideoGenerationInputURLValidationError.invalidURL
        }
        guard let scheme: String = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw VideoGenerationInputURLValidationError.unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw VideoGenerationInputURLValidationError.userInfoNotAllowed
        }
        guard let host: String = components.host?.lowercased(), host.isEmpty == false else {
            throw VideoGenerationInputURLValidationError.missingHost
        }

        components.scheme = scheme
        components.host = host
        components.fragment = nil
        guard let submissionString: String = components.string,
              let evaluatedURL: URL = URL(string: submissionString),
              evaluatedURL.absoluteString == submissionString else {
            throw VideoGenerationInputURLValidationError.invalidURL
        }
        return VideoGenerationInputURL(
            evaluatedURL: evaluatedURL,
            submissionString: submissionString
        )
    }
}
