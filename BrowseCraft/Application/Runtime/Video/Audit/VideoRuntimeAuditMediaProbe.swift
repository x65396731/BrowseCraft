import Foundation

// 中文注释：只在显式 audit session 内使用（BC-EVIDENCE-076.4）：对既有执行链解析出的最终媒体
// 候选做有界原生观察——HLS 读初始 manifest 与首个媒体引用各一次，MP4 读有界字节并验 ftyp。
// 永不请求 key URI、key bytes、IV、live refresh 或解密明文；unknown 不改写为 unencrypted。
struct VideoRuntimeAuditMediaObservation: Sendable {
    let mediaKind: VideoRuntimeEvidenceMediaKind
    let finalURL: URL
    let bytesRead: Int
    let contentType: String
    let manifestPassed: Bool?
    let firstMediaReferencePassed: Bool?
    let encryptionStatus: VideoRuntimeEvidenceEncryptionStatus
}

enum VideoRuntimeAuditMediaProbeFailure: Error, Equatable {
    case unsupportedMediaKind
    case mediaResponseUnreadable
    case contentTypeMismatch
    case manifestUnreadable
    case firstMediaReferenceUnreadable
    case invalidMP4Signature

    // 中文注释：脱敏 kebab-case 原因码（BC-EVIDENCE-024），不携带 URL 或正文。
    var rejectionReasonCode: String {
        switch self {
        case .unsupportedMediaKind:
            return "unsupported-media-kind"
        case .mediaResponseUnreadable:
            return "media-response-unreadable"
        case .contentTypeMismatch:
            return "media-content-type-mismatch"
        case .manifestUnreadable:
            return "manifest-unreadable"
        case .firstMediaReferenceUnreadable:
            return "first-media-reference-unreadable"
        case .invalidMP4Signature:
            return "invalid-mp4-signature"
        }
    }
}

struct VideoRuntimeAuditMediaProbe {
    static let maximumReadByteCount: Int = 256 * 1_024

    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func observe(
        mediaURL: URL,
        kind: VideoRuntimeEvidenceMediaKind,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async -> Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> {
        switch kind {
        case .hls:
            return await self.observeHLS(
                manifestURL: mediaURL,
                playbackRequestConfig: playbackRequestConfig
            )
        case .mp4:
            return await self.observeMP4(
                mediaURL: mediaURL,
                playbackRequestConfig: playbackRequestConfig
            )
        case .unknown:
            return .failure(.unsupportedMediaKind)
        }
    }

    /// 中文注释：BC-EVIDENCE-077.4——WebUI 路线的最终媒体 URL 来自播放中元素的 currentSrc，
    /// 没有 catalog 声明的种类；这里按**响应内容**嗅探（HLS Content-Type 或 `#EXTM3U`；
    /// MP4 Content-Type 或 `ftyp`），不用扩展名词表，随后走与 076.4 完全相同的有界验收。
    func observeSniffingKind(
        mediaURL: URL,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async -> Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> {
        guard let response = await self.boundedGET(
            url: mediaURL,
            playbackRequestConfig: playbackRequestConfig
        ) else {
            return .failure(.mediaResponseUnreadable)
        }
        let firstLine: String = String(decoding: response.data.prefix(16), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        if Self.contentTypeMatchesHLS(response.contentType) || firstLine.hasPrefix("#EXTM3U") {
            return await self.observeHLS(
                manifestResponse: response,
                playbackRequestConfig: playbackRequestConfig
            )
        }
        if response.contentType.lowercased().contains("mp4") || Self.hasFtypSignature(response.data) {
            return self.observeMP4(response: response)
        }
        return .failure(.unsupportedMediaKind)
    }

    private func observeHLS(
        manifestURL: URL,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async -> Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> {
        guard let manifestResponse = await self.boundedGET(
            url: manifestURL,
            playbackRequestConfig: playbackRequestConfig
        ) else {
            return .failure(.mediaResponseUnreadable)
        }
        return await self.observeHLS(
            manifestResponse: manifestResponse,
            playbackRequestConfig: playbackRequestConfig
        )
    }

    private func observeHLS(
        manifestResponse: BoundedResponse,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async -> Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> {
        guard Self.contentTypeMatchesHLS(manifestResponse.contentType) else {
            return .failure(.contentTypeMismatch)
        }
        let manifestText: String = String(decoding: manifestResponse.data, as: UTF8.self)
        let manifestLines: [String] = manifestText
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let firstLine: String = manifestLines.first,
              firstLine.trimmingCharacters(
                  in: CharacterSet(charactersIn: "\u{feff}")
              ) == "#EXTM3U" else {
            return .failure(.manifestUnreadable)
        }
        guard let firstReference: String = manifestLines.first(where: { line in
            line.isEmpty == false && line.hasPrefix("#") == false
        }), let firstReferenceURL: URL = URL(
            string: firstReference,
            relativeTo: manifestResponse.finalURL
        )?.absoluteURL else {
            return .failure(.firstMediaReferenceUnreadable)
        }
        guard let referenceResponse = await self.boundedGET(
            url: firstReferenceURL,
            playbackRequestConfig: playbackRequestConfig
        ), referenceResponse.data.isEmpty == false else {
            return .failure(.firstMediaReferenceUnreadable)
        }

        let classification: VideoHLSInitialManifestClassification =
            VideoHLSManifestEncryptionClassifier.classify(manifestText)
        return .success(
            VideoRuntimeAuditMediaObservation(
                mediaKind: .hls,
                finalURL: manifestResponse.finalURL,
                bytesRead: manifestResponse.data.count + referenceResponse.data.count,
                contentType: manifestResponse.contentType,
                manifestPassed: true,
                firstMediaReferencePassed: true,
                encryptionStatus: classification == .encrypted ? .encrypted : .unknown
            )
        )
    }

    private func observeMP4(
        mediaURL: URL,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async -> Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> {
        guard let response = await self.boundedGET(
            url: mediaURL,
            playbackRequestConfig: playbackRequestConfig
        ) else {
            return .failure(.mediaResponseUnreadable)
        }
        return self.observeMP4(response: response)
    }

    private func observeMP4(
        response: BoundedResponse
    ) -> Result<VideoRuntimeAuditMediaObservation, VideoRuntimeAuditMediaProbeFailure> {
        guard response.data.isEmpty == false else {
            return .failure(.mediaResponseUnreadable)
        }
        guard response.contentType.lowercased().contains("mp4") else {
            #if DEBUG
            // 中文注释：只记录 Content-Type 值用于归因，不记录 URL。
            AppDebugLog.write(
                "[BrowseCraftRuntimeAudit] mp4 probe content-type mismatch: \(response.contentType)"
            )
            #endif
            return .failure(.contentTypeMismatch)
        }
        guard Self.hasFtypSignature(response.data) else {
            return .failure(.invalidMP4Signature)
        }
        return .success(
            VideoRuntimeAuditMediaObservation(
                mediaKind: .mp4,
                finalURL: response.finalURL,
                bytesRead: response.data.count,
                contentType: response.contentType,
                manifestPassed: nil,
                firstMediaReferencePassed: nil,
                encryptionStatus: .notApplicable
            )
        )
    }

    private struct BoundedResponse {
        let data: Data
        let contentType: String
        let finalURL: URL
    }

    private func boundedGET(
        url: URL,
        playbackRequestConfig: SourcePlaybackRequestConfig?
    ) async -> BoundedResponse? {
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in playbackRequestConfig?.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let referer: URL = playbackRequestConfig?.referer,
           request.value(forHTTPHeaderField: "Referer") == nil {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        if let userAgent: String = playbackRequestConfig?.userAgent,
           request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        do {
            let (bytes, response): (URLSession.AsyncBytes, URLResponse) =
                try await self.session.bytes(for: request)
            guard let httpResponse: HTTPURLResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
                return nil
            }
            var data: Data = Data()
            data.reserveCapacity(min(Self.maximumReadByteCount, 64 * 1_024))
            for try await byte: UInt8 in bytes {
                data.append(byte)
                if data.count >= Self.maximumReadByteCount {
                    break
                }
            }
            guard let contentType: String = httpResponse.value(
                forHTTPHeaderField: "Content-Type"
            ), contentType.isEmpty == false else {
                return nil
            }
            return BoundedResponse(
                data: data,
                contentType: contentType,
                finalURL: httpResponse.url ?? url
            )
        } catch {
            return nil
        }
    }

    private static func contentTypeMatchesHLS(_ contentType: String) -> Bool {
        let mediaType: String = contentType
            .lowercased()
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return mediaType.contains("mpegurl") || mediaType.contains("m3u8")
    }

    private static func hasFtypSignature(_ data: Data) -> Bool {
        guard data.count >= 12 else {
            return false
        }
        let signature: Data = data.subdata(in: 4..<8)
        return signature == Data("ftyp".utf8)
    }
}
