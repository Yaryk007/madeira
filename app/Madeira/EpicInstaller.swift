// SPDX-License-Identifier: GPL-3.0-or-later
// GameHub: downloading an Epic game (manifest, chunks, files), as Legendary does.

import Foundation
import CryptoKit
import Compression

/// Epic's build manifest: the game's files, each made of parts of chunks that
/// sit on Epic's CDN. Binary manifests (the usual kind) and JSON ones both parse.
struct EpicManifest {
    struct Chunk { let guid: String; let hash: UInt64; let group: UInt8; let windowSize: UInt32; let fileSize: Int64 }
    struct Part { let guid: String; let offset: UInt32; let size: UInt32 }
    struct File { let name: String; let sha1: Data; let parts: [Part]; var size: Int64 { parts.reduce(0) { $0 + Int64($1.size) } } }

    var featureLevel: UInt32 = 0
    var appName = ""
    var buildVersion = ""
    var launchExe = ""
    var launchCommand = ""
    var chunks: [String: Chunk] = [:]
    var files: [File] = []

    var installSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var downloadSize: Int64 { chunks.values.reduce(0) { $0 + $1.fileSize } }

    /// The CDN folder for this manifest version.
    var chunkDirectory: String {
        featureLevel >= 15 ? "ChunksV4" : featureLevel >= 6 ? "ChunksV3" : featureLevel >= 3 ? "ChunksV2" : "Chunks"
    }
    func chunkPath(_ chunk: Chunk) -> String {
        String(format: "%@/%02d/%016llX_%@.chunk", chunkDirectory, chunk.group, chunk.hash, chunk.guid)
    }

    // MARK: Binary manifest

    init(data: Data) throws {
        var probe = EpicReader(data)
        if try probe.u32() == 0x44BEC00C { try self.init(binary: data) } else { try self.init(json: data) }
    }

    private init(binary data: Data) throws {
        var header = EpicReader(data)
        _ = try header.u32()
        let headerSize = Int(try header.u32())
        let uncompressed = Int(try header.u32())
        let compressed = Int(try header.u32())
        _ = try header.bytes(20)
        let storedAs = try header.u8()
        var body = data.subdata(in: (data.startIndex + headerSize)..<min(data.endIndex, data.startIndex + headerSize + compressed))
        if storedAs & 1 != 0 { body = try EpicInflate.zlib(body, size: uncompressed) }
        var r = EpicReader(body)

        // Meta
        let metaStart = r.offset
        let metaSize = Int(try r.u32())
        let dataVersion = try r.u8()
        featureLevel = try r.u32()
        _ = try r.u8()                       // is file data
        _ = try r.u32()                      // app id
        appName = try r.fstring()
        buildVersion = try r.fstring()
        launchExe = try r.fstring()
        launchCommand = try r.fstring()
        _ = dataVersion
        r.offset = metaStart + metaSize

        // Chunk data list (columns of `count` values each)
        let cdlStart = r.offset
        let cdlSize = Int(try r.u32())
        _ = try r.u8()
        let chunkCount = Int(try r.u32())
        var guids: [String] = []
        for _ in 0..<chunkCount { guids.append(try r.guid()) }
        var hashes: [UInt64] = []
        for _ in 0..<chunkCount { hashes.append(try r.u64()) }
        r.offset += chunkCount * 20          // SHA-1s
        var groups: [UInt8] = []
        for _ in 0..<chunkCount { groups.append(try r.u8()) }
        var windows: [UInt32] = []
        for _ in 0..<chunkCount { windows.append(try r.u32()) }
        var sizes: [Int64] = []
        for _ in 0..<chunkCount { sizes.append(Int64(bitPattern: try r.u64())) }
        for i in 0..<chunkCount {
            chunks[guids[i]] = Chunk(guid: guids[i], hash: hashes[i], group: groups[i], windowSize: windows[i], fileSize: sizes[i])
        }
        r.offset = cdlStart + cdlSize

        // File manifest list (also columns)
        let fmlStart = r.offset
        let fmlSize = Int(try r.u32())
        _ = try r.u8()
        let fileCount = Int(try r.u32())
        var names: [String] = []
        for _ in 0..<fileCount { names.append(try r.fstring()) }
        for _ in 0..<fileCount { _ = try r.fstring() }                       // symlink targets
        var shas: [Data] = []
        for _ in 0..<fileCount { shas.append(try r.bytes(20)) }
        r.offset += fileCount                                                 // flags
        for _ in 0..<fileCount { let n = try r.u32(); for _ in 0..<n { _ = try r.fstring() } }   // install tags
        var partsList: [[Part]] = []
        for _ in 0..<fileCount {
            let n = Int(try r.u32())
            var parts: [Part] = []
            for _ in 0..<n {
                let start = r.offset
                let size = Int(try r.u32())
                let guid = try r.guid()
                let offset = try r.u32()
                let length = try r.u32()
                parts.append(Part(guid: guid, offset: offset, size: length))
                r.offset = start + size
            }
            partsList.append(parts)
        }
        for i in 0..<fileCount { files.append(File(name: names[i], sha1: shas[i], parts: partsList[i])) }
        r.offset = fmlStart + fmlSize
    }

    // MARK: JSON manifest (older builds)

    private init(json data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EpicError.message("The game's manifest could not be read.")
        }
        // JSON manifests store numbers as runs of 3-digit decimal bytes, little-endian.
        func blob(_ s: Any?) -> [UInt8] {
            guard let s = s as? String else { return [] }
            return stride(from: 0, to: s.count - 2, by: 3).compactMap { i in
                UInt8(s[s.index(s.startIndex, offsetBy: i)..<s.index(s.startIndex, offsetBy: i + 3)])
            }
        }
        func number(_ s: Any?) -> UInt64 { blob(s).enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) } }
        featureLevel = UInt32(number(object["ManifestFileVersion"]))
        appName = object["AppNameString"] as? String ?? ""
        buildVersion = object["BuildVersionString"] as? String ?? ""
        launchExe = object["LaunchExeString"] as? String ?? ""
        launchCommand = object["LaunchCommand"] as? String ?? ""
        let hashes = object["ChunkHashList"] as? [String: String] ?? [:]
        let groups = object["DataGroupList"] as? [String: String] ?? [:]
        let sizes = object["ChunkFilesizeList"] as? [String: String] ?? [:]
        for (guid, hash) in hashes {
            chunks[guid] = Chunk(guid: guid, hash: number(hash), group: UInt8(number(groups[guid] ?? "")),
                                 windowSize: 1_048_576, fileSize: Int64(number(sizes[guid] ?? "")))
        }
        for file in object["FileManifestList"] as? [[String: Any]] ?? [] {
            let parts = (file["FileChunkParts"] as? [[String: Any]] ?? []).map {
                Part(guid: $0["Guid"] as? String ?? "", offset: UInt32(number($0["Offset"])), size: UInt32(number($0["Size"])))
            }
            files.append(File(name: file["Filename"] as? String ?? "", sha1: Data(blob(file["FileHash"])), parts: parts))
        }
    }
}

/// Little-endian reads over a manifest.
struct EpicReader {
    let data: Data
    var offset: Int
    init(_ data: Data) { self.data = data; offset = data.startIndex }
    private mutating func take(_ n: Int) throws -> Data {
        guard n >= 0, offset + n <= data.endIndex else { throw EpicError.message("The game's manifest is shorter than expected.") }
        defer { offset += n }
        return data.subdata(in: offset..<(offset + n))
    }
    mutating func u8() throws -> UInt8 { try take(1)[0] }
    mutating func u32() throws -> UInt32 { try take(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian }
    mutating func u64() throws -> UInt64 { try take(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian }
    mutating func bytes(_ n: Int) throws -> Data { try take(n) }
    /// Epic's GUIDs, four 32-bit words in upper-case hex.
    mutating func guid() throws -> String { String(format: "%08X%08X%08X%08X", try u32(), try u32(), try u32(), try u32()) }
    /// Unreal's FString: a signed length with the terminator; negative means UTF-16.
    mutating func fstring() throws -> String {
        let length = Int(Int32(bitPattern: try u32()))
        if length == 0 { return "" }
        if length < 0 {
            let raw = try take(-length * 2)
            return String(data: raw.dropLast(2), encoding: .utf16LittleEndian) ?? ""
        }
        let raw = try take(length)
        return String(decoding: raw.dropLast(), as: UTF8.self)
    }
}

enum EpicInflate {
    /// zlib data (a 2-byte header, then DEFLATE) to `size` bytes.
    static func zlib(_ data: Data, size: Int) throws -> Data {
        guard data.count > 2 else { throw EpicError.message("A download was empty.") }
        let deflate = data.dropFirst(2)
        var out = Data(count: max(size, 1))
        let written = out.withUnsafeMutableBytes { dst in
            deflate.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, deflate.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw EpicError.message("A download did not unpack (\(written) of \(size) bytes).") }
        return out
    }

    /// A chunk file: its header, then the (usually compressed) data.
    static func chunk(_ data: Data) throws -> Data {
        var r = EpicReader(data)
        guard try r.u32() == 0xB1FE3AA2 else { throw EpicError.message("A chunk from Epic's servers was not valid.") }
        let version = try r.u32()
        let headerSize = Int(try r.u32())
        let compressed = Int(try r.u32())
        _ = try r.guid()
        _ = try r.u64()
        let storedAs = try r.u8()
        var uncompressed = 1_048_576
        if version >= 2 { _ = try r.bytes(21) }
        if version >= 3 { uncompressed = Int(try r.u32()) }
        let body = data.subdata(in: (data.startIndex + headerSize)..<min(data.endIndex, data.startIndex + headerSize + compressed))
        return storedAs & 1 != 0 ? try zlib(body, size: uncompressed) : body
    }
}

/// Installs and tracks Epic games in drive_c/Epic/<app>.
@MainActor final class EpicInstaller: ObservableObject {
    static let shared = EpicInstaller()
    struct Progress: Equatable { var done: Int64; var total: Int64; var phase: String }
    @Published private(set) var progress: [String: Progress] = [:]
    @Published var failure: (app: String, message: String)?
    private var tasks: [String: Task<Void, Never>] = [:]

    nonisolated static var root: URL { LibraryModel.drive.appendingPathComponent("Epic", isDirectory: true) }
    nonisolated static func folder(_ app: String) -> URL { root.appendingPathComponent(app, isDirectory: true) }

    func installing(_ app: String) -> Bool { progress[app] != nil }

    /// The manifest of a game's current build and the CDN base its chunks come from.
    func manifest(for game: EpicGame) async throws -> (EpicManifest, [URL]) {
        let url = "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/public/assets/v2/platform/Windows"
            + "/namespace/\(game.namespace)/catalogItem/\(game.catalogItemId)/app/\(game.appName)/label/Live"
        let assets = try await EpicStore.shared.get(url) as? [String: Any] ?? [:]
        guard let element = (assets["elements"] as? [[String: Any]])?.first,
              let manifests = element["manifests"] as? [[String: Any]], !manifests.isEmpty else {
            throw EpicError.message("Epic has no Windows build of this game for this account.")
        }
        var lastError: Error = EpicError.message("The game's manifest could not be downloaded.")
        var bases: [URL] = []
        for entry in manifests {
            guard let uri = entry["uri"] as? String, var parts = URLComponents(string: uri) else { continue }
            if let base = URL(string: String(uri.split(separator: "?")[0]))?.deletingLastPathComponent() { bases.append(base) }
            let params = (entry["queryParams"] as? [[String: Any]] ?? []).compactMap { p -> URLQueryItem? in
                guard let name = p["name"] as? String else { return nil }
                return URLQueryItem(name: name, value: p["value"] as? String)
            }
            if !params.isEmpty { parts.queryItems = params }
            guard let manifestURL = parts.url else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: manifestURL)
                return (try EpicManifest(data: data), bases)
            } catch { lastError = error }
        }
        throw lastError
    }

    func install(_ game: EpicGame, added: @escaping (LibraryEntry) -> Void) {
        guard tasks[game.appName] == nil else { return }
        progress[game.appName] = Progress(done: 0, total: 0, phase: "Preparing…")
        tasks[game.appName] = Task { [weak self] in
            do {
                guard let self else { return }
                let (manifest, bases) = try await self.manifest(for: game)
                let app = game.appName
                // The files are written off the main thread; progress comes back a few times a second.
                try await Self.download(app, manifest: manifest, bases: bases) { done, total in
                    Task { @MainActor in
                        if EpicInstaller.shared.progress[app] != nil {
                            EpicInstaller.shared.progress[app] = Progress(done: done, total: total, phase: "Downloading")
                        }
                    }
                }
                let entry = Self.entry(game, manifest: manifest)
                added(entry)
                LogStore.shared.log("[epic] installed \(game.appName) build \(manifest.buildVersion) (\(manifest.files.count) files)")
            } catch is CancellationError {
                LogStore.shared.log("[epic] install of \(game.appName) cancelled")
            } catch {
                self?.failure = (game.appName, error.localizedDescription)
                LogStore.shared.log("[epic] install of \(game.appName) failed: \(error.localizedDescription)", level: .error)
            }
            self?.progress[game.appName] = nil
            self?.tasks[game.appName] = nil
        }
    }

    func cancel(_ app: String) { tasks[app]?.cancel() }

    /// Every file from its chunk parts. Chunks download a few at a time ahead of
    /// the file being written, are kept while a later part still needs them, and
    /// each file is checked against the manifest's SHA-1. A file already there
    /// with the right size is kept, so a stopped install resumes.
    nonisolated private static func download(_ app: String, manifest: EpicManifest, bases: [URL],
                                             report: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let folder = Self.folder(app)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        if free > 0 && free < manifest.installSize + 512 * 1_048_576 {
            throw EpicError.message("Not enough storage: the game needs \(ByteCountFormatter.string(fromByteCount: manifest.installSize, countStyle: .file)).")
        }
        let total = manifest.installSize
        var done: Int64 = 0
        var reported = Date.distantPast
        report(0, total)

        // Files still to write, and how many parts of each chunk they use.
        let pending = manifest.files.filter { file in
            let url = folder.appendingPathComponent(file.name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
            if size == file.size { done += file.size; return false }
            return true
        }
        var uses: [String: Int] = [:]
        for file in pending { for part in file.parts { uses[part.guid, default: 0] += 1 } }
        var seen = Set<String>(), order: [String] = []
        for file in pending { for part in file.parts where seen.insert(part.guid).inserted { order.append(part.guid) } }
        let fetcher = EpicChunkFetcher(manifest: manifest, bases: bases, order: order)

        for file in pending {
            try Task.checkCancellation()
            let url = folder.appendingPathComponent(file.name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            var sha = Insecure.SHA1()
            for part in file.parts {
                let chunk = try await fetcher.chunk(part.guid)
                let start = Int(part.offset), end = start + Int(part.size)
                guard end <= chunk.count else { throw EpicError.message("A chunk of \(file.name) was shorter than expected.") }
                let slice = chunk.subdata(in: start..<end)
                try handle.write(contentsOf: slice)
                sha.update(data: slice)
                uses[part.guid, default: 1] -= 1
                if uses[part.guid] == 0 { await fetcher.release(part.guid) }
                done += Int64(part.size)
                if Date().timeIntervalSince(reported) > 0.25 { reported = Date(); report(done, total) }
            }
            try handle.close()
            if !file.sha1.isEmpty && Data(sha.finalize()) != file.sha1 {
                try? FileManager.default.removeItem(at: url)
                throw EpicError.message("\(file.name) did not match Epic's checksum. Try the install again.")
            }
        }
        await fetcher.finish()
        report(total, total)
    }

    /// The library entry for an installed game: its launch program and arguments.
    static func entry(_ game: EpicGame, manifest: EpicManifest) -> LibraryEntry {
        let exe = manifest.launchExe.replacingOccurrences(of: "\\", with: "/")
        var entry = LibraryModel.shared.entries.first { $0.epicApp == game.appName }
            ?? LibraryEntry(title: game.title, relativePath: "Epic/\(game.appName)/\(exe)", bits: 64)
        entry.relativePath = "Epic/\(game.appName)/\(exe)"
        entry.epicApp = game.appName
        entry.epicNamespace = game.namespace
        if entry.arguments.isEmpty { entry.arguments = manifest.launchCommand }
        entry.folderBytes = manifest.installSize
        return entry
    }
}

/// Downloads chunks ahead of the writer, a few at a time, keeping them in
/// memory only until their last part is written.
actor EpicChunkFetcher {
    private let manifest: EpicManifest
    private let bases: [URL]
    private let order: [String]
    private var next = 0
    private var ready: [String: Task<Data, Error>] = [:]
    private let ahead = 6

    init(manifest: EpicManifest, bases: [URL], order: [String]) {
        self.manifest = manifest; self.bases = bases; self.order = order
    }

    func chunk(_ guid: String) async throws -> Data {
        // Keep up to `ahead` chunks in flight past the one asked for.
        if ready[guid] == nil { ready[guid] = fetch(guid) }
        while next < order.count && ready.count < ahead {
            let id = order[next]; next += 1
            if ready[id] == nil { ready[id] = fetch(id) }
        }
        return try await ready[guid]!.value
    }

    func release(_ guid: String) { ready[guid] = nil }

    func finish() { for task in ready.values { task.cancel() }; ready = [:] }

    private func fetch(_ guid: String) -> Task<Data, Error> {
        guard let chunk = manifest.chunks[guid] else {
            return Task { throw EpicError.message("The manifest names a chunk it does not list.") }
        }
        let path: String = manifest.chunkPath(chunk)
        let bases = self.bases
        return Task {
            var lastError: Error = EpicError.message("A chunk could not be downloaded.")
            for attempt in 0..<3 {
                for base in bases {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: base.appendingPathComponent(path))
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                        return try EpicInflate.chunk(data)
                    } catch { lastError = error }
                }
                try await Task.sleep(for: .seconds(Double(attempt + 1)))
            }
            throw lastError
        }
    }
}
