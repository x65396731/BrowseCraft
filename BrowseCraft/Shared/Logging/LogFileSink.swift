import BrowseCraftLog
import Foundation

// 中文注释：本机滚动日志文件（Logging-Design.md 第 6 节，BCA-OBS-016）。只收 info 及以上，每行一条 JSON；
// Caches/Logs 下两个文件轮换，单个到 5 MB 时把当前文件挪成旧文件、另起新文件，合计不超过 10 MB。
// Caches 目录本就不进 iCloud 备份，这里再显式标一次排除备份。设置页「导出诊断日志」把两个文件按时间先后合成一份交给分享面板。

/// 中文注释：`@unchecked` 的依据（architecture.md 第 4 节）：文件句柄与目录只在 `lock` 内读写；
/// 写入由日志的后台串行队列调用，导出与删除来自主线程，三者经同一把锁互斥。
final class LogFileSink: LogSink, @unchecked Sendable {
    static let fileSizeLimitBytes: Int = 5 * 1024 * 1024

    let minimumLevel: LogLevel = .info
    private let directory: URL
    private let fileManager: FileManager = FileManager.default
    private let lock: NSLock = NSLock()
    private var handle: FileHandle?
    private var currentSize: Int = 0

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    private var currentFileURL: URL {
        return self.directory.appendingPathComponent("browsecraft-0.log")
    }

    private var previousFileURL: URL {
        return self.directory.appendingPathComponent("browsecraft-1.log")
    }

    func write(_ record: LogRecord) {
        guard let line: Data = (record.jsonLine + "\n").data(using: .utf8) else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        do {
            if self.currentSize + line.count > Self.fileSizeLimitBytes {
                try self.rotate()
            }
            let handle: FileHandle = try self.openHandleIfNeeded()
            try handle.write(contentsOf: line)
            self.currentSize += line.count
        } catch {
            // 不记：出口自己不得回调 AppLog，写失败只能丢掉这一条；下一条会重新打开文件
            self.handle = nil
        }
    }

    /// 中文注释：导出前调用方先 `AppLog.flush()`；旧文件在前、当前文件在后，合成一份放进临时目录。
    func makeExportFile() throws -> URL {
        self.lock.lock()
        defer { self.lock.unlock() }
        try? self.handle?.synchronize() // try?: 只是尽量落盘，导出读到的是已写入的部分
        var combined: Data = Data()
        for url: URL in [self.previousFileURL, self.currentFileURL] where self.fileManager.fileExists(atPath: url.path) {
            combined.append(try Data(contentsOf: url))
        }
        let stamp: String = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let exportURL: URL = self.fileManager.temporaryDirectory
            .appendingPathComponent("BrowseCraft-diagnostics-\(stamp).log")
        try combined.write(to: exportURL, options: .atomic)
        return exportURL
    }

    /// 中文注释：删除账号时清掉本机日志（BCA-OBS-016）；之后的记录写进新文件。
    func removeAllFiles() {
        self.lock.lock()
        defer { self.lock.unlock() }
        try? self.handle?.close() // try?: 关闭失败不影响随后的删除
        self.handle = nil
        self.currentSize = 0
        for url: URL in [self.previousFileURL, self.currentFileURL] {
            try? self.fileManager.removeItem(at: url) // try?: 文件可能本就不存在
        }
    }

    private func openHandleIfNeeded() throws -> FileHandle {
        if let handle: FileHandle = self.handle {
            return handle
        }
        try self.fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var directoryURL: URL = self.directory
        var values: URLResourceValues = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directoryURL.setResourceValues(values) // try?: Caches 本就不进备份，这里只是再保险
        if self.fileManager.fileExists(atPath: self.currentFileURL.path) == false {
            self.fileManager.createFile(atPath: self.currentFileURL.path, contents: nil)
        }
        let handle: FileHandle = try FileHandle(forWritingTo: self.currentFileURL)
        self.currentSize = Int(try handle.seekToEnd())
        self.handle = handle
        return handle
    }

    private func rotate() throws {
        try? self.handle?.close() // try?: 关闭失败不影响轮换
        self.handle = nil
        if self.fileManager.fileExists(atPath: self.previousFileURL.path) {
            try self.fileManager.removeItem(at: self.previousFileURL)
        }
        if self.fileManager.fileExists(atPath: self.currentFileURL.path) {
            try self.fileManager.moveItem(at: self.currentFileURL, to: self.previousFileURL)
        }
        self.currentSize = 0
    }

    private static func defaultDirectory() -> URL {
        let caches: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Logs", isDirectory: true)
    }
}
