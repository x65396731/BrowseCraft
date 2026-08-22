import Darwin
import Foundation

struct PublicURLPolicy: PublicURLChecking {
    func validate(_ url: URL) throws {
        guard let scheme: String = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw PublicURLCheckError.unsupportedScheme
        }
        guard url.user == nil, url.password == nil else {
            throw PublicURLCheckError.userInfoNotAllowed
        }
        guard let host: String = url.host?.lowercased(), host.isEmpty == false else {
            throw PublicURLCheckError.missingHost
        }
        guard self.isLocalHostName(host) == false else {
            throw PublicURLCheckError.localHost
        }

        if let literalAddress: [UInt8] = self.literalAddress(host) {
            guard self.isPublicAddress(literalAddress) else {
                throw PublicURLCheckError.nonPublicAddress
            }
            return
        }

        let resolvedAddresses: [[UInt8]] = try self.resolve(host)
        guard resolvedAddresses.isEmpty == false else {
            throw PublicURLCheckError.resolutionFailed
        }
        guard resolvedAddresses.allSatisfy(self.isPublicAddress) else {
            throw PublicURLCheckError.nonPublicAddress
        }
    }

    func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool {
        guard let candidateHost: String = candidate.host?.lowercased(),
              let inputHost: String = inputURL.host?.lowercased() else {
            return false
        }
        return candidateHost == inputHost
            || candidateHost.hasSuffix(".\(inputHost)")
            || inputHost.hasSuffix(".\(candidateHost)")
    }

    private func isLocalHostName(_ host: String) -> Bool {
        return host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal")
            || host.hasSuffix(".lan")
            || host.hasSuffix(".home.arpa")
    }

    private func literalAddress(_ host: String) -> [UInt8]? {
        var ipv4: in_addr = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return withUnsafeBytes(of: &ipv4) { bytes in Array(bytes) }
        }

        var ipv6: in6_addr = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            return withUnsafeBytes(of: &ipv6) { bytes in Array(bytes) }
        }
        return nil
    }

    private func resolve(_ host: String) throws -> [[UInt8]] {
        var hints: addrinfo = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var result: UnsafeMutablePointer<addrinfo>?
        let status: Int32 = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let first: UnsafeMutablePointer<addrinfo> = result else {
            throw PublicURLCheckError.resolutionFailed
        }
        defer {
            freeaddrinfo(first)
        }

        var addresses: [[UInt8]] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info: UnsafeMutablePointer<addrinfo> = current {
            guard let socketAddress: UnsafeMutablePointer<sockaddr> = info.pointee.ai_addr else {
                current = info.pointee.ai_next
                continue
            }
            if info.pointee.ai_family == AF_INET {
                var address: in_addr = UnsafeRawPointer(socketAddress)
                    .assumingMemoryBound(to: sockaddr_in.self)
                    .pointee
                    .sin_addr
                addresses.append(withUnsafeBytes(of: &address) { bytes in Array(bytes) })
            } else if info.pointee.ai_family == AF_INET6 {
                var address: in6_addr = UnsafeRawPointer(socketAddress)
                    .assumingMemoryBound(to: sockaddr_in6.self)
                    .pointee
                    .sin6_addr
                addresses.append(withUnsafeBytes(of: &address) { bytes in Array(bytes) })
            }
            current = info.pointee.ai_next
        }
        return Array(Set(addresses))
    }

    private func isPublicAddress(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4:
            return self.isPublicIPv4(bytes)
        case 16:
            return self.isPublicIPv6(bytes)
        default:
            return false
        }
    }

    private func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        let first: UInt8 = bytes[0]
        let second: UInt8 = bytes[1]
        if first == 0 || first == 10 || first == 127 || first >= 224 {
            return false
        }
        if first == 100 && (64...127).contains(second) {
            return false
        }
        if first == 169 && second == 254 {
            return false
        }
        if first == 172 && (16...31).contains(second) {
            return false
        }
        if first == 192 && second == 168 {
            return false
        }
        if first == 192 && second == 0 && bytes[2] == 0 {
            return false
        }
        if first == 192 && second == 0 && bytes[2] == 2 {
            return false
        }
        if first == 192 && second == 88 && bytes[2] == 99 {
            return false
        }
        if first == 198 && (second == 18 || second == 19) {
            return false
        }
        if first == 198 && second == 51 && bytes[2] == 100 {
            return false
        }
        if first == 203 && second == 0 && bytes[2] == 113 {
            return false
        }
        return true
    }

    private func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        if bytes.allSatisfy({ $0 == 0 }) {
            return false
        }
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 {
            return false
        }
        if bytes[0] & 0xFE == 0xFC {
            return false
        }
        if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 {
            return false
        }
        if bytes[0] == 0xFF {
            return false
        }
        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8 {
            return false
        }
        let ipv4MappedPrefix: [UInt8] = Array(repeating: 0, count: 10) + [0xFF, 0xFF]
        if Array(bytes.prefix(12)) == ipv4MappedPrefix {
            return self.isPublicIPv4(Array(bytes.suffix(4)))
        }
        let wellKnownNAT64Prefix: [UInt8] = [0x00, 0x64, 0xFF, 0x9B]
            + Array(repeating: 0, count: 8)
        if Array(bytes.prefix(12)) == wellKnownNAT64Prefix {
            return self.isPublicIPv4(Array(bytes.suffix(4)))
        }
        return true
    }
}
