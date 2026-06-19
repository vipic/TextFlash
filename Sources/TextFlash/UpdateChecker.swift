import AppKit
import Foundation
import OSLog

final class UpdateChecker {
    static let shared = UpdateChecker()

    private let log = Logger(subsystem: "com.nekutai.textflash", category: "update")
    private let session: URLSession
    private let lastCheckKey = "TextFlashLastUpdateCheck"
    private let lastReleaseNotesKey = "TextFlashLastReleaseNotes"
    private let checkInterval: TimeInterval = 86_400

    var isDevBuild: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.contains("-dev")
    }

    struct ReleaseInfo: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int
        }
    }

    struct UpdateResult {
        let currentVersion: String
        let latestVersion: String
        let releaseNotes: String
        let downloadURL: String
        let downloadSize: Int
        let htmlURL: String
    }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    func checkForUpdate(force: Bool = false) async -> UpdateResult? {
        guard !isDevBuild else {
            log.info("开发版本，跳过更新检查")
            return nil
        }

        let now = Date()
        if !force {
            let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
            if now.timeIntervalSince(lastCheck) < checkInterval {
                log.info("距上次检查不足 24 小时，跳过")
                return nil
            }
        }

        guard let release = await fetchLatestRelease() else { return nil }
        UserDefaults.standard.set(now, forKey: lastCheckKey)

        let currentVersion = currentVersionString()
        guard Self.isNewer(tag: release.tag_name, than: currentVersion) else {
            cacheResult(release)
            return nil
        }

        guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            log.error("Release 中没有找到 DMG 文件")
            return nil
        }

        return UpdateResult(
            currentVersion: currentVersion,
            latestVersion: Self.displayVersion(release.tag_name),
            releaseNotes: release.body ?? "",
            downloadURL: dmg.browser_download_url,
            downloadSize: dmg.size,
            htmlURL: release.html_url
        )
    }

    func cachedReleaseNotes() -> String? {
        UserDefaults.standard.string(forKey: lastReleaseNotesKey)
    }

    func lastCheckDate() -> Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    func downloadBinary(from urlString: String, expectedSize: Int, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw UpdateError.insecureURL
        }

        let delegate = StreamingDownloadDelegate(expectedSize: expectedSize, onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        return try await delegate.download(from: url, using: session)
    }

    func applyUpdate(dmgAt tempURL: URL, expectedVersion: String) throws {
        let stableDMG = URL(fileURLWithPath: NSTemporaryDirectory() + "textflash_update.dmg")
        try? FileManager.default.removeItem(at: stableDMG)
        try FileManager.default.moveItem(at: tempURL, to: stableDMG)

        let scriptPath = NSTemporaryDirectory() + "textflash_update.sh"
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: stableDMG.path,
            targetPath: Bundle.main.bundlePath,
            expectedVersion: Self.displayVersion(expectedVersion),
            currentPID: ProcessInfo.processInfo.processIdentifier
        )

        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        task.arguments = ["/bin/bash", scriptPath]
        try task.run()

        NSApp.terminate(nil)
    }

    static func isNewer(tag: String, than current: String) -> Bool {
        let tagParts = displayVersion(tag).split(separator: ".")
        let currentParts = displayVersion(current).split(separator: ".")

        for i in 0..<max(tagParts.count, currentParts.count) {
            let tagValue = i < tagParts.count ? (Int(tagParts[i]) ?? 0) : 0
            let currentValue = i < currentParts.count ? (Int(currentParts[i]) ?? 0) : 0
            if tagValue > currentValue { return true }
            if tagValue < currentValue { return false }
        }
        return false
    }

    static func displayVersion(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^v+"#, with: "", options: .regularExpression)
    }

    fileprivate static func downloadProgress(totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64, expectedSize: Int) -> Double? {
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expectedSize)
        guard totalBytes > 0 else { return nil }
        let progress = Double(totalBytesWritten) / Double(totalBytes)
        return min(max(progress, 0), 0.99)
    }

    private func currentVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func cacheResult(_ result: ReleaseInfo) {
        UserDefaults.standard.set(result.body, forKey: lastReleaseNotesKey)
    }

    private func fetchLatestRelease() async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/vipic/TextFlash/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TextFlash/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                log.error("GitHub API 返回非 200")
                return nil
            }
            return try JSONDecoder().decode(ReleaseInfo.self, from: data)
        } catch {
            log.error("获取 Release 失败: \(error.localizedDescription)")
            return nil
        }
    }

    enum UpdateError: LocalizedError, Equatable {
        case invalidURL
        case insecureURL
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return L10n.t("update.error.invalidURL")
            case .insecureURL: return L10n.t("update.error.insecureURL")
            case .downloadFailed: return L10n.t("update.error.downloadFailed")
            }
        }
    }
}

private final class StreamingDownloadDelegate: NSObject, URLSessionDataDelegate {
    private let onProgress: (@Sendable (Double) -> Void)?
    private let expectedSize: Int
    private var lastProgress = 0.0
    private var totalBytesWritten: Int64 = 0
    private var totalBytesExpectedToWrite: Int64 = 0
    private var continuation: CheckedContinuation<URL, Error>?
    private var fileURL: URL?
    private var fileHandle: FileHandle?
    private var didReceiveSuccessfulResponse = false
    private var didFinish = false

    init(expectedSize: Int, onProgress: (@Sendable (Double) -> Void)?) {
        self.expectedSize = expectedSize
        self.onProgress = onProgress
    }

    func download(from url: URL, using session: URLSession) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("textflash-update-\(UUID().uuidString).dmg")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)

        do {
            fileHandle = try FileHandle(forWritingTo: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        fileURL = tempURL

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            completionHandler(.cancel)
            finish(with: UpdateChecker.UpdateError.downloadFailed)
            return
        }

        didReceiveSuccessfulResponse = true
        totalBytesExpectedToWrite = response.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
        } catch {
            dataTask.cancel()
            finish(with: error)
            return
        }

        totalBytesWritten += Int64(data.count)
        guard let progress = UpdateChecker.downloadProgress(
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite,
            expectedSize: expectedSize
        ), progress > lastProgress else {
            return
        }

        lastProgress = progress
        onProgress?(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        if let error {
            finish(with: error)
            return
        }
        guard didReceiveSuccessfulResponse, let fileURL else {
            finish(with: UpdateChecker.UpdateError.downloadFailed)
            return
        }

        onProgress?(1.0)
        finish(with: fileURL)
    }

    private func finish(with url: URL) {
        guard !didFinish else { return }
        didFinish = true
        closeFile()
        continuation?.resume(returning: url)
        continuation = nil
    }

    private func finish(with error: Error) {
        guard !didFinish else { return }
        didFinish = true
        closeFile()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
