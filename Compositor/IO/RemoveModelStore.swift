import Foundation
import CryptoKit
import Observation

/// The LaMa inpainting model the Remove tool needs: not bundled (196 MB), but downloaded once into
/// Application Support on first use, with progress, a checksum check and a retry on failure.
///
/// The zip is self-hosted on this fork's GitHub Releases (the model itself is jerhoads/lama-coreml
/// on Hugging Face; LaMa weights are Apache-2.0). The SHA-256 below pins the bytes, so a swapped or
/// truncated download is rejected before unpacking. The API asset URL is the fallback: github.com's
/// release-redirect host is unreachable from some networks while api.github.com still answers.
@MainActor @Observable
final class RemoveModelStore {
    static let shared = RemoveModelStore()

    /// What the sheet shows; nil shows no sheet.
    enum Stage: Equatable {
        case confirm
        case downloading(Double)
        /// Downloaded, checksum done: unpacking is indeterminate but short.
        case unpacking
        case failed(String)
    }
    var stage: Stage?

    nonisolated static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Compositor/Models", isDirectory: true)
    nonisolated static let modelURL = directory.appendingPathComponent("LaMa.mlpackage", isDirectory: true)
    nonisolated static var isAvailable: Bool { FileManager.default.fileExists(atPath: modelURL.path) }
    private nonisolated static let zipURL = directory.appendingPathComponent("LaMa.mlpackage.zip")
    /// SHA-256 of LaMa.mlpackage.zip, from the release's own SHA256SUMS.
    private nonisolated static let zipSHA256 = "d0f4ef099b68f592bf7d2c8f601c546cc1ed97675914d4c3eeae2755df28c8f6"
    private nonisolated static let downloadURLs = [
        URL(string: "https://github.com/mainanamisa/compositor-cn/releases/download/v1.4.5-cn/LaMa.mlpackage.zip")!,
        URL(string: "https://api.github.com/repos/mainanamisa/compositor-cn/releases/assets/620760761")!
    ]

    enum Failure: LocalizedError {
        case download, checksum, unpacking
        var errorDescription: String? {
            switch self {
            case .download: "无法下载模型文件，请检查网络连接"
            case .checksum: "下载的模型文件校验失败，可能已损坏"
            case .unpacking: "无法解压模型文件"
            }
        }
    }

    /// Resumes the removal waiting on this answer: true once the model is on disk.
    private var continuation: CheckedContinuation<Bool, Never>?
    private var downloadTask: Task<Void, Never>?

    /// True once the model is on disk, asking to download it first when it isn't.
    func ensureAvailable() async -> Bool {
        guard !Self.isAvailable else { return true }
        guard continuation == nil else { return false }
        stage = .confirm
        return await withCheckedContinuation { continuation = $0 }
    }

    /// The sheet's 下载 / 重试.
    func download() {
        guard downloadTask == nil else { return }
        stage = .downloading(0)
        downloadTask = Task {
            await performDownload()
            downloadTask = nil
        }
    }

    /// The sheet's 取消, or closing it: the waiting removal is told there's no model.
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        stage = nil
        continuation?.resume(returning: false)
        continuation = nil
        try? FileManager.default.removeItem(at: Self.zipURL)
    }

    private func finish(_ available: Bool) {
        stage = nil
        continuation?.resume(returning: available)
        continuation = nil
    }

    private func performDownload() async {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try await fetchZip()
            try Task.checkCancellation()
            stage = .unpacking
            try await unzipAndVerify()
            try? FileManager.default.removeItem(at: Self.zipURL)
            finish(true)
        } catch is CancellationError {
            // cancel() already answered the waiting removal and cleaned up.
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func fetchZip() async throws {
        var lastError: Error = Failure.download
        for url in Self.downloadURLs {
            do {
                try await fetch(url, to: Self.zipURL)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Streams the zip to disk, reporting progress into the sheet every few hundred KB. A stall
    /// resumes where it left off (GitHub answers Range requests) — on a slow or flaky connection
    /// a fresh 196 MB start rarely survives.
    private func fetch(_ url: URL, to destination: URL) async throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        var received = (try? FileHandle(forReadingFrom: destination).seekToEnd()) ?? 0
        var total: Int64 = -1
        var attempts = 0
        while true {
            do {
                var request = URLRequest(url: url)
                // GitHub's asset API serves the bytes only when asked for them this way.
                if url.host == "api.github.com" { request.setValue("application/octet-stream", forHTTPHeaderField: "Accept") }
                if received > 0 { request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 206 else {
                    throw Failure.download
                }
                if received > 0, http.statusCode == 200 {
                    // The Range request was ignored: anything on disk is the old beginning, start over.
                    received = 0
                    try? FileManager.default.removeItem(at: destination)
                    FileManager.default.createFile(atPath: destination.path, contents: nil)
                }
                if total < 0 { total = http.expectedContentLength + Int64(received) }
                let handle = try FileHandle(forWritingTo: destination)
                do {
                    try handle.seekToEnd()
                    var chunk = Data()
                    chunk.reserveCapacity(1 << 20)
                    for try await byte in bytes {
                        chunk.append(byte)
                        if chunk.count >= 1 << 20 {
                            try handle.write(contentsOf: chunk)
                            received += UInt64(chunk.count)
                            chunk.removeAll(keepingCapacity: true)
                            if total > 0 { stage = .downloading(Double(received) / Double(total)) }
                        }
                    }
                    if !chunk.isEmpty { try handle.write(contentsOf: chunk); received += UInt64(chunk.count) }
                    try handle.close()
                } catch {
                    try? handle.close()
                    throw error
                }
                if total > 0 { stage = .downloading(1) }
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempts += 1
                guard attempts < 8 else { throw Failure.download }
                try await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// The checksum runs before unpacking, and the unpacked package must look like a model.
    private func unzipAndVerify() async throws {
        let digest = try await Task.detached(priority: .userInitiated) { () throws -> String in
            var hasher = SHA256()
            let handle = try FileHandle(forReadingFrom: Self.zipURL)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1 << 22), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
        guard digest == Self.zipSHA256 else { throw Failure.checksum }
        try Task.checkCancellation()
        let unpacked = Self.directory.appendingPathComponent("LaMa.mlpackage", isDirectory: true)
        try? FileManager.default.removeItem(at: unpacked)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", Self.zipURL.path, Self.directory.path]
        try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
            unzip.terminationHandler = { process in
                process.terminationStatus == 0
                    ? completion.resume()
                    : completion.resume(throwing: Failure.unpacking)
            }
            do { try unzip.run() } catch { completion.resume(throwing: error) }
        }
        guard Self.isAvailable else { throw Failure.unpacking }
    }
}
