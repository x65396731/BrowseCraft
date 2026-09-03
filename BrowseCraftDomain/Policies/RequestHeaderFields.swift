import Foundation

public enum RequestHeaderFields: Sendable {
    public static func applyingOverrides(
        _ overrides: [String: String]?,
        to headers: [String: String]
    ) -> [String: String] {
        var resolvedHeaders: [String: String] = headers
        overrides?.forEach { key, value in
            self.setHeader(key, value: value, in: &resolvedHeaders)
        }
        return resolvedHeaders
    }

    public static func containsHeader(_ name: String, in headers: [String: String]) -> Bool {
        return headers.keys.contains { key in
            return key.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    public static func originHeader(from url: URL?) -> String? {
        guard let url: URL,
              let scheme: String = url.scheme,
              let host: String = url.host else {
            return nil
        }

        var origin: String = "\(scheme)://\(host)"
        if let port: Int = url.port {
            origin += ":\(port)"
        }
        return origin
    }

    private static func setHeader(_ name: String, value: String, in headers: inout [String: String]) {
        if let existingKey: String = headers.keys.first(where: { key in
            return key.caseInsensitiveCompare(name) == .orderedSame
        }) {
            headers[existingKey] = value
        } else {
            headers[name] = value
        }
    }
}
