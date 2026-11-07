// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Glass: importing games. Folders and programs move in; archives unpack by the
// rules in GlassArchive.swift. RAR and 7z go through the system's libarchive, opened at
// run time so that a system without it only loses those two formats.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Darwin

// MARK: - libarchive

/// The few libarchive calls used here, looked up by name.
private final class LibArchive {
    typealias Ptr = OpaquePointer
    typealias ReadCB = @convention(c) (Ptr?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?) -> Int
    typealias SeekCB = @convention(c) (Ptr?, UnsafeMutableRawPointer?, Int64, Int32) -> Int64

    let new: @convention(c) () -> Ptr?
    let supportFilterAll: @convention(c) (Ptr?) -> Int32
    let supportFormatAll: @convention(c) (Ptr?) -> Int32
    let setRead: @convention(c) (Ptr?, ReadCB?) -> Int32
    let setSeek: @convention(c) (Ptr?, SeekCB?) -> Int32
    let setData: @convention(c) (Ptr?, UnsafeMutableRawPointer?) -> Int32
    let open1: @convention(c) (Ptr?) -> Int32
    let openFilenames: @convention(c) (Ptr?, UnsafePointer<UnsafePointer<CChar>?>?, Int) -> Int32
    let nextHeader: @convention(c) (Ptr?, UnsafeMutablePointer<Ptr?>?) -> Int32
    let readData: @convention(c) (Ptr?, UnsafeMutableRawPointer?, Int) -> Int
    let skip: @convention(c) (Ptr?) -> Int32
    let free: @convention(c) (Ptr?) -> Int32
    let errorString: @convention(c) (Ptr?) -> UnsafePointer<CChar>?
    let pathname: @convention(c) (Ptr?) -> UnsafePointer<CChar>?
    let pathnameUTF8: @convention(c) (Ptr?) -> UnsafePointer<CChar>?
    let size: @convention(c) (Ptr?) -> Int64
    let filetype: @convention(c) (Ptr?) -> UInt32
    let isEncrypted: @convention(c) (Ptr?) -> Int32

    static let shared: LibArchive? = LibArchive()

    private init?() {
        guard let lib = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, as _: T.Type = T.self) -> T? {
            dlsym(lib, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let new: @convention(c) () -> Ptr? = sym("archive_read_new"),
              let supportFilterAll: @convention(c) (Ptr?) -> Int32 = sym("archive_read_support_filter_all"),
              let supportFormatAll: @convention(c) (Ptr?) -> Int32 = sym("archive_read_support_format_all"),
              let setRead: @convention(c) (Ptr?, ReadCB?) -> Int32 = sym("archive_read_set_read_callback"),
              let setSeek: @convention(c) (Ptr?, SeekCB?) -> Int32 = sym("archive_read_set_seek_callback"),
              let setData: @convention(c) (Ptr?, UnsafeMutableRawPointer?) -> Int32 = sym("archive_read_set_callback_data"),
              let open1: @convention(c) (Ptr?) -> Int32 = sym("archive_read_open1"),
              let openFilenames: @convention(c) (Ptr?, UnsafePointer<UnsafePointer<CChar>?>?, Int) -> Int32 = sym("archive_read_open_filenames"),
              let nextHeader: @convention(c) (Ptr?, UnsafeMutablePointer<Ptr?>?) -> Int32 = sym("archive_read_next_header"),
              let readData: @convention(c) (Ptr?, UnsafeMutableRawPointer?, Int) -> Int = sym("archive_read_data"),
              let skip: @convention(c) (Ptr?) -> Int32 = sym("archive_read_data_skip"),
              let free: @convention(c) (Ptr?) -> Int32 = sym("archive_read_free"),
              let errorString: @convention(c) (Ptr?) -> UnsafePointer<CChar>? = sym("archive_error_string"),
              let pathname: @convention(c) (Ptr?) -> UnsafePointer<CChar>? = sym("archive_entry_pathname"),
              let pathnameUTF8: @convention(c) (Ptr?) -> UnsafePointer<CChar>? = sym("archive_entry_pathname_utf8"),
              let size: @convention(c) (Ptr?) -> Int64 = sym("archive_entry_size"),
              let filetype: @convention(c) (Ptr?) -> UInt32 = sym("archive_entry_filetype"),
              let isEncrypted: @convention(c) (Ptr?) -> Int32 = sym("archive_entry_is_encrypted")
        else { return nil }
        self.new = new; self.supportFilterAll = supportFilterAll; self.supportFormatAll = supportFormatAll
        self.setRead = setRead; self.setSeek = setSeek; self.setData = setData; self.open1 = open1
        self.openFilenames = openFilenames; self.nextHeader = nextHeader; self.readData = readData
        self.skip = skip; self.free = free; self.errorString = errorString; self.pathname = pathname
        self.pathnameUTF8 = pathnameUTF8; self.size = size; self.filetype = filetype; self.isEncrypted = isEncrypted
    }
}

/// libarchive reads through this, so the read position is known and what is behind it can be freed.
private final class ArchiveSource {
    let fd: Int32
    let length: Int64
    var position: Int64 = 0
    var buffer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 16)
    init(fd: Int32, length: Int64) { self.fd = fd; self.length = length }
    deinit { buffer.deallocate() }
}

enum GlassRar {
    private static let endOfArchive: Int32 = 1, fatal: Int32 = -30, failed: Int32 = -25, retry: Int32 = -10

    private static let read: LibArchive.ReadCB = { _, client, out in
        let source = Unmanaged<ArchiveSource>.fromOpaque(client!).takeUnretainedValue()
        let n = pread(source.fd, source.buffer, 1 << 20, off_t(source.position))
        guard n >= 0 else { return -1 }
        source.position += Int64(n)
        out?.pointee = UnsafeRawPointer(source.buffer)
        return n
    }
    private static let seek: LibArchive.SeekCB = { _, client, offset, whence in
        let source = Unmanaged<ArchiveSource>.fromOpaque(client!).takeUnretainedValue()
        switch whence {
        case SEEK_SET: source.position = offset
        case SEEK_CUR: source.position += offset
        case SEEK_END: source.position = source.length + offset
        default: return -1
        }
        return source.position
    }

    /// All the parts of a multi-part RAR beside `first`, in order; just `first` otherwise.
    static func volumes(of first: URL) -> [URL] {
        let name = first.lastPathComponent
        guard let range = name.range(of: #"\.part0*1\.rar$"#, options: [.regularExpression, .caseInsensitive]) else { return [first] }
        let stem = String(name[..<range.lowerBound])
        let folder = first.deletingLastPathComponent()
        let digits = name[range].filter(\.isNumber).count
        var parts: [URL] = []
        var index = 1
        while true {
            let part = folder.appendingPathComponent(stem + ".part" + String(format: "%0\(digits)d", index) + ".rar")
            guard FileManager.default.fileExists(atPath: part.path) else { break }
            parts.append(part); index += 1
        }
        return parts.isEmpty ? [first] : parts
    }

    static var available: Bool { LibArchive.shared != nil }

    private static func opened(_ urls: [URL], source: ArchiveSource?) throws -> OpaquePointer {
        guard let lib = LibArchive.shared, let archive = lib.new() else {
            throw GlassArchiveError.unsupported("a format this iOS version doesn't include")
        }
        _ = lib.supportFilterAll(archive); _ = lib.supportFormatAll(archive)
        var status: Int32
        if let source {
            _ = lib.setRead(archive, read); _ = lib.setSeek(archive, seek)
            _ = lib.setData(archive, Unmanaged.passUnretained(source).toOpaque())
            status = lib.open1(archive)
        } else {
            let names = urls.map { strdup($0.path) }
            defer { names.forEach { Foundation.free($0) } }
            var list: [UnsafePointer<CChar>?] = names.map { UnsafePointer($0) } + [nil]
            status = list.withUnsafeMutableBufferPointer { lib.openFilenames(archive, $0.baseAddress, 1 << 20) }
        }
        guard status >= 0 else {
            let why = lib.errorString(archive).map { String(cString: $0) } ?? "unknown error"
            _ = lib.free(archive)
            throw GlassArchiveError.unreadable(why)
        }
        return archive
    }

    /// What the archive holds when unpacked. Reads through it, which takes as long as decoding for a solid RAR.
    static func unpackedSize(_ urls: [URL], cancelled: () -> Bool) throws -> Int64 {
        guard let lib = LibArchive.shared else { throw GlassArchiveError.unsupported("a format this iOS version doesn't include") }
        let archive = try opened(urls, source: nil)
        defer { _ = lib.free(archive) }
        var total: Int64 = 0
        var entry: OpaquePointer?
        while true {
            if cancelled() { throw GlassArchiveError.cancelled }
            let status = lib.nextHeader(archive, &entry)
            if status == endOfArchive { return total }
            guard status > failed, status != retry else {
                throw GlassArchiveError.unreadable(lib.errorString(archive).map { String(cString: $0) } ?? "unknown error")
            }
            if lib.isEncrypted(entry) > 0 { throw GlassArchiveError.encrypted }
            total += max(0, lib.size(entry))
            _ = lib.skip(archive)
        }
    }

    /// Unpacks `urls` into `destination`. `free` asks for the read part of a single-file
    /// archive to be punched out as it goes (GlassExtractMode.punching).
    static func unpack(_ urls: [URL], destination: URL, free freeing: Bool,
                       progress: (GlassExtractProgress) -> Void, cancelled: () -> Bool) throws {
        guard let lib = LibArchive.shared else { throw GlassArchiveError.unsupported("a format this iOS version doesn't include") }
        let fm = FileManager.default
        let total = urls.reduce(Int64(0)) { $0 + GlassImporter.fileSize($1) }

        var source: ArchiveSource?
        var fd: Int32 = -1
        if urls.count == 1 {
            fd = open(urls[0].path, freeing ? O_RDWR : O_RDONLY)
            guard fd >= 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
            source = ArchiveSource(fd: fd, length: total)
        }
        defer { if fd >= 0 { close(fd) } }
        let archive = try opened(urls, source: source)
        defer { _ = lib.free(archive) }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var punched: Int64 = 0
        let holdBack: Int64 = 8 << 20    // what libarchive may still be holding from the read-ahead
        var data = [UInt8](repeating: 0, count: 1 << 20)
        var entry: OpaquePointer?
        var written: Int64 = 0
        var lastReport = Date.distantPast
        while true {
            if cancelled() { throw GlassArchiveError.cancelled }
            let status = lib.nextHeader(archive, &entry)
            if status == endOfArchive { break }
            guard status > failed, status != retry else {
                throw GlassArchiveError.unreadable(lib.errorString(archive).map { String(cString: $0) } ?? "unknown error")
            }
            if lib.isEncrypted(entry) > 0 { throw GlassArchiveError.encrypted }
            let raw = (lib.pathnameUTF8(entry) ?? lib.pathname(entry)).map { String(cString: $0) } ?? ""
            guard let relative = glassSafeRelativePath(raw) else { _ = lib.skip(archive); continue }
            let target = destination.appendingPathComponent(relative)
            let type = lib.filetype(entry)
            if type == 0o040000 {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            guard type == 0o100000 else { _ = lib.skip(archive); continue }   // links have no place in a game folder
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let out = open(target.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            guard out >= 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
            defer { close(out) }
            while true {
                if cancelled() { throw GlassArchiveError.cancelled }
                let n = data.withUnsafeMutableBytes { lib.readData(archive, $0.baseAddress, 1 << 20) }
                if n == 0 { break }
                guard n > 0 else {
                    // libarchive checks each RAR file's CRC; a mismatch lands here.
                    throw GlassArchiveError.damaged(relative)
                }
                var done = 0
                while done < n {
                    let w = data.withUnsafeBytes { Darwin.write(out, $0.baseAddress! + done, n - done) }
                    if w < 0, errno == EINTR { continue }
                    guard w > 0 else {
                        if errno == ENOSPC { throw GlassArchiveError.noSpace(needed: Int64(n), free: 0) }
                        throw GlassArchiveError.unreadable(String(cString: strerror(errno)))
                    }
                    done += w
                }
                written += Int64(n)
                if Date().timeIntervalSince(lastReport) > 0.15 {
                    lastReport = Date()
                    let read = source?.position ?? 0
                    let fraction = total > 0 && source != nil ? Double(read) / Double(total) : 0
                    progress(GlassExtractProgress(fraction: fraction, file: relative))
                }
            }
            guard fsync(out) == 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
            // Only once a whole file is safely out, and never the read-ahead.
            if freeing, let source {
                let end = (source.position - holdBack) & ~Int64(0xffff)
                if end > punched {
                    var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: off_t(punched), fp_length: off_t(end - punched))
                    if fcntl(fd, F_PUNCHHOLE, &hole) == 0 { punched = end }
                }
            }
        }
        progress(GlassExtractProgress(fraction: 1, file: ""))
    }
}

// MARK: - Importer

/// One import in the Downloads panel.
struct GlassImportJob: Identifiable, Equatable {
    enum State: Equatable { case checking, needsApproval, running, finishing, done, failed(String) }
    let id = UUID()
    var name: String
    var fraction = 0.0
    var file = ""
    var state = State.checking
    var note = ""
}

@MainActor final class GlassImporter: ObservableObject {
    static let shared = GlassImporter()
    @Published private(set) var jobs: [GlassImportJob] = []
    /// A RAR that needs the path which cannot resume: the player has to agree first.
    @Published var approval: GlassImportJob?
    private var approved: [UUID: CheckedContinuation<Bool, Never>] = [:]

    static let stagingFolder = LibraryModel.documents.appendingPathComponent(".glass-import", isDirectory: true)
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z"]

    /// What can be picked in the Files app.
    static var pickerTypes: [UTType] {
        var types: [UTType] = [.folder, .zip, .data]
        if let rar = UTType(filenameExtension: "rar") { types.append(rar) }
        if let seven = UTType(filenameExtension: "7z") { types.append(seven) }
        return types
    }

    nonisolated static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
    nonisolated static func freeBytes() -> Int64 {
        let values = try? LibraryModel.documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Archives waiting in Madeira's own folder (put there with the Files app, or left by a stop).
    static func waitingArchives() -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        for folder in [LibraryModel.documents, stagingFolder] {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            found += items.filter { archiveExtensions.contains($0.pathExtension.lowercased()) && !isLaterVolume($0) }
        }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isLaterVolume(_ url: URL) -> Bool {
        url.lastPathComponent.range(of: #"\.part0*[2-9][0-9]*\.rar$|\.part0*1[0-9]+\.rar$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func answer(approve: Bool) {
        guard let job = approval else { return }
        approval = nil
        approved.removeValue(forKey: job.id)?.resume(returning: approve)
    }

    func cancel(_ id: UUID) { CancelBox.shared.insert(id) }

    func dismiss(_ id: UUID) { jobs.removeAll { $0.id == id } }

    private func update(_ id: UUID, _ change: (inout GlassImportJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    /// Imports a picked item. `scoped` is whether it came from the Files picker.
    func start(_ url: URL, scoped: Bool) {
        let job = GlassImportJob(name: url.deletingPathExtension().lastPathComponent)
        jobs.append(job)
        let id = job.id
        Task.detached(priority: .userInitiated) { [self] in
            let access = scoped && url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let background = await beginBackground()
            defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(background) } }
            do {
                let folder = try await run(url, id: id)
                await finish(folder, id: id)
            } catch {
                await update(id) { $0.state = .failed(error.localizedDescription) }
            }
        }
    }

    private func beginBackground() -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: "glass-import", expirationHandler: nil)
    }

    private nonisolated static func gamesFolder() throws -> URL {
        let folder = LibraryModel.drive.appendingPathComponent("Games", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private nonisolated static func destination(for name: String) throws -> URL {
        let games = try gamesFolder()
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        var target = games.appendingPathComponent(clean.isEmpty ? "Game" : clean, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = games.appendingPathComponent("\(clean) \(n)", isDirectory: true); n += 1
        }
        return target
    }

    /// Moving costs no storage; only a file from another volume (iCloud, a USB drive) is copied.
    private nonisolated static func bringIn(_ url: URL, to target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if url.standardizedFileURL == target.standardizedFileURL { return }
        do { try fm.moveItem(at: url, to: target) } catch {
            try fm.copyItem(at: url, to: target)
            try? fm.removeItem(at: url)
        }
    }

    private nonisolated func run(_ url: URL, id: UUID) async throws -> URL {
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isFolder)

        if isFolder.boolValue {
            let target = try Self.destination(for: url.lastPathComponent)
            await update(id) { $0.state = .finishing; $0.note = "Moving the folder in" }
            try Self.bringIn(url, to: target)
            return target
        }
        let ext = url.pathExtension.lowercased()
        if LibraryModel.programExtensions.contains(ext) {
            // A program needs the files beside it.
            let parent = url.deletingLastPathComponent()
            let target = try Self.destination(for: parent.lastPathComponent)
            await update(id) { $0.state = .finishing; $0.note = "Moving the game's folder in" }
            try Self.bringIn(parent, to: target)
            return target
        }
        guard Self.archiveExtensions.contains(ext) else {
            throw GlassArchiveError.unsupported("a file type (.\(ext)) that isn't a game or an archive")
        }
        return ext == "zip" ? try await unpackZip(url, id: id) : try await unpackOther(url, id: id)
    }

    private nonisolated func stage(_ url: URL) throws -> URL {
        let staged = Self.stagingFolder.appendingPathComponent(url.lastPathComponent)
        if url.path.hasPrefix(Self.stagingFolder.path) { return url }
        try Self.bringIn(url, to: staged)
        return staged
    }

    private nonisolated func unpackZip(_ url: URL, id: UUID) async throws -> URL {
        let staged = try stage(url)
        let journalURL = GlassZip.journalURL(for: staged)
        // A stopped import continues into the folder it started.
        if let data = try? Data(contentsOf: journalURL), let journal = try? JSONDecoder().decode(GlassZip.Journal.self, from: data) {
            let target = URL(fileURLWithPath: journal.destination, isDirectory: true)
            await update(id) { $0.state = .running; $0.note = "Continuing where it stopped" }
            try await extractZip(staged, to: target, mode: journal.mode, id: id)
            return target
        }
        let fd = open(staged.path, O_RDONLY)
        guard fd >= 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
        let entries: [GlassZipEntry]
        do { entries = try GlassZip.directory(fd: fd, size: UInt64(Self.fileSize(staged))); close(fd) } catch { close(fd); throw error }
        guard GlassZip.nativelyReadable(entries) else { return try await unpackOther(staged, id: id) }
        if entries.contains(where: { $0.flags & 1 != 0 }) { throw GlassArchiveError.encrypted }

        let unpacked = entries.reduce(Int64(0)) { $0 + Int64($1.size) }
        let free = Self.freeBytes(), margin: Int64 = 256 << 20
        let mode: GlassExtractMode
        if free >= unpacked + margin { mode = .keepUntilDone } else {
            let peak = GlassZip.peakExtraBytes(entries)
            guard free >= peak + margin else { throw GlassArchiveError.noSpace(needed: peak + margin, free: free) }
            mode = .truncating
        }
        let target = try Self.destination(for: staged.deletingPathExtension().lastPathComponent)
        await update(id) {
            $0.state = .running
            $0.note = mode == .truncating ? "Freeing the archive as it unpacks" : "Unpacking"
        }
        try await extractZip(staged, to: target, mode: mode, id: id)
        return target
    }

    private nonisolated func extractZip(_ archive: URL, to target: URL, mode: GlassExtractMode, id: UUID) async throws {
        let reporter = ProgressRelay { [self] progress in
            Task { @MainActor in update(id) { $0.fraction = progress.fraction; $0.file = progress.file } }
        }
        try GlassZip.unpack(archive: archive, destination: target, mode: mode,
                            progress: reporter.send, cancelled: { CancelBox.shared.contains(id) })
    }

    private nonisolated func unpackOther(_ url: URL, id: UUID) async throws -> URL {
        guard GlassRar.available else { throw GlassArchiveError.unsupported("a format this iOS version doesn't include") }
        let isRar = url.pathExtension.lowercased() == "rar"
        var parts = GlassRar.volumes(of: url)
        parts = try parts.map { try stage($0) }
        let packed = parts.reduce(Int64(0)) { $0 + Self.fileSize($1) }
        let free = Self.freeBytes(), margin: Int64 = 256 << 20

        // Unknown until read. Three times the archive covers nearly all games and skips a slow extra pass.
        var freeing = false
        if free < packed * 3 + margin {
            await update(id) { $0.note = "Measuring the archive" }
            let unpacked = try GlassRar.unpackedSize(parts) { CancelBox.shared.contains(id) }
            if free < unpacked + margin {
                guard isRar, parts.count == 1, free + packed >= unpacked + margin else {
                    throw GlassArchiveError.noSpace(needed: unpacked + margin, free: free)
                }
                guard await askApproval(id) else { throw GlassArchiveError.cancelled }
                freeing = true
            }
        }
        let stem = parts[0].deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"\.part0*1$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let target = try Self.destination(for: stem)
        await update(id) { $0.state = .running; $0.note = freeing ? "Freeing the archive as it unpacks" : "Unpacking" }
        let reporter = ProgressRelay { [self] progress in
            Task { @MainActor in update(id) { $0.fraction = progress.fraction; $0.file = progress.file } }
        }
        do {
            try GlassRar.unpack(parts, destination: target, free: freeing, progress: reporter.send,
                                cancelled: { CancelBox.shared.contains(id) })
        } catch {
            // Kept only when the archive is whole: a partial folder would look like a game.
            if !freeing { try? FileManager.default.removeItem(at: target) }
            throw error
        }
        parts.forEach { try? FileManager.default.removeItem(at: $0) }
        return target
    }

    private func askApproval(_ id: UUID) async -> Bool {
        guard let job = jobs.first(where: { $0.id == id }) else { return false }
        update(id) { $0.state = .needsApproval }
        return await withCheckedContinuation { continuation in
            approved[id] = continuation
            approval = job
        }
    }

    /// Picks the program and adds the game to the library.
    private func finish(_ folder: URL, id: UUID) {
        update(id) { $0.state = .finishing; $0.note = "Adding it to your library" }
        do {
            guard let program = Self.mainProgram(in: folder) else {
                throw GlassArchiveError.unsupported("no Windows program (.exe) inside")
            }
            var entry = try LibraryModel.inspect(program)
            entry.title = folder.lastPathComponent
            LibraryModel.shared.save(entry, metadata: true)
            update(id) { $0.state = .done; $0.fraction = 1; $0.note = "Added to your library"; $0.file = "" }
        } catch {
            update(id) { $0.state = .failed(error.localizedDescription) }
        }
    }

    /// The likeliest game program: helpers and installers ruled out, then the shallowest and largest.
    nonisolated static func mainProgram(in folder: URL) -> URL? {
        let skip = ["unins", "crashhandler", "crashreport", "redist", "vcredist", "dxsetup", "dotnet", "setup",
                    "ue4prereq", "uecrash", "launcherhelper", "cefsubprocess", "updater"]
        var candidates: [(url: URL, depth: Int, size: Int64)] = []
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        while let item = walker?.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "exe" else { continue }
            let name = item.lastPathComponent.lowercased()
            if skip.contains(where: name.contains) { continue }
            let depth = item.pathComponents.count - folder.pathComponents.count
            candidates.append((item, depth, fileSize(item)))
        }
        return candidates.sorted { $0.depth != $1.depth ? $0.depth < $1.depth : $0.size > $1.size }.first?.url
    }
}

/// Thread-safe set of stopped imports, read from the extraction threads.
final class CancelBox: @unchecked Sendable {
    static let shared = CancelBox()
    private let lock = NSLock()
    private var ids = Set<UUID>()
    func insert(_ id: UUID) { lock.lock(); ids.insert(id); lock.unlock() }
    func contains(_ id: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return ids.contains(id) }
}

private final class ProgressRelay: @unchecked Sendable {
    private let handler: @Sendable (GlassExtractProgress) -> Void
    init(_ handler: @escaping @Sendable (GlassExtractProgress) -> Void) { self.handler = handler }
    func send(_ progress: GlassExtractProgress) { handler(progress) }
}
