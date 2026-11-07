// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Glass: extracting game archives without needing room for two copies.
//
// Deleting the archive only after everything is out needs archive + game on disk at
// once, which a big game on a phone often cannot afford. Deleting each file from the
// archive as it comes out frees that space along the way. Whether that is safe
// depends on the format, so there are three paths:
//
//  - Enough room for both: extract, verify, then delete the archive. Nothing is at
//    risk until the game is known to be complete. Every format uses this when it can.
//  - ZIP without that room: files are independent, so they come out LAST FIRST. After
//    a file is written, CRC-checked and flushed, the archive is truncated to where that
//    file began. Truncating is one cheap call on any file system, the part of the
//    archive that is left stays intact, and the file list is kept in a journal, so a
//    crash or a killed app resumes where it stopped: whatever lies beyond the archive's
//    current length is already out.
//  - RAR without that room: a solid RAR can only be decoded front to back and each file
//    depends on the ones before it, so the order cannot be reversed and a stopped run
//    cannot resume. The part already read is punched out of the file (F_PUNCHHOLE) to
//    free it. This is the one path that can lose the archive, so the player is told and
//    has to agree first. 7z keeps its index at the end and needs random access, so it
//    is never freed while extracting.
//
// None of this changes the game's files: each one ends up byte for byte what was packed.

import Foundation
import zlib
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum GlassArchiveError: LocalizedError {
    case unreadable(String), encrypted, unsupported(String), noSpace(needed: Int64, free: Int64), damaged(String), cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "This archive can't be read: \(why)"
        case .encrypted: return "This archive is password protected. Extract it elsewhere first."
        case .unsupported(let what): return "This archive uses \(what), which Madeira can't unpack."
        case .noSpace(let needed, let free):
            let f = ByteCountFormatter()
            return "Not enough storage: this needs \(f.string(fromByteCount: needed)), and \(f.string(fromByteCount: free)) is free."
        case .damaged(let file): return "\(file) is damaged in the archive."
        case .cancelled: return "Stopped."
        }
    }
}

/// How an archive will be unpacked.
enum GlassExtractMode: String, Codable {
    /// Extract, verify, delete the archive afterwards.
    case keepUntilDone
    /// ZIP: last file first, truncating as it goes. Resumes after a crash.
    case truncating
    /// RAR: front to back, punching out what was read. Cannot resume.
    case punching
}

struct GlassExtractProgress {
    var fraction: Double
    var file: String
}

/// A name from inside an archive, made safe to join to the destination: no absolute
/// paths, no way out of the folder through "..".
func glassSafeRelativePath(_ raw: String) -> String? {
    var parts: [String] = []
    for part in raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true) {
        if part == "." { continue }
        if part == ".." { return nil }
        parts.append(String(part))
    }
    if let first = parts.first, first.hasSuffix(":") { parts.removeFirst() }   // C:\...
    return parts.isEmpty ? nil : parts.joined(separator: "/")
}

// MARK: - ZIP

struct GlassZipEntry: Codable {
    var name: String
    var method: UInt16
    var flags: UInt16
    var crc: UInt32
    var compressed: UInt64
    var size: UInt64
    var offset: UInt64
    var isDirectory: Bool { name.hasSuffix("/") }
}

enum GlassZip {
    private static func le16(_ d: [UInt8], _ i: Int) -> UInt16 { UInt16(d[i]) | UInt16(d[i + 1]) << 8 }
    private static func le32(_ d: [UInt8], _ i: Int) -> UInt32 {
        UInt32(d[i]) | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2]) << 16 | UInt32(d[i + 3]) << 24
    }
    private static func le64(_ d: [UInt8], _ i: Int) -> UInt64 {
        UInt64(le32(d, i)) | UInt64(le32(d, i + 4)) << 32
    }

    private static func read(_ fd: Int32, at offset: UInt64, count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var done = 0
        while done < count {
            let n = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + done, count - done, off_t(offset) + off_t(done)) }
            if n < 0, errno == EINTR { continue }
            if n <= 0 { throw GlassArchiveError.unreadable("it ends early") }
            done += n
        }
        return buffer
    }

    /// The archive's file list, from its central directory.
    static func directory(fd: Int32, size fileSize: UInt64) throws -> [GlassZipEntry] {
        guard fileSize >= 22 else { throw GlassArchiveError.unreadable("it is too short to be a ZIP") }
        let tailSize = Int(min(fileSize, 65_557))
        let tailStart = fileSize - UInt64(tailSize)
        let tail = try read(fd, at: tailStart, count: tailSize)
        var eocd = -1
        var i = tailSize - 22
        while i >= 0 {
            if tail[i] == 0x50, tail[i + 1] == 0x4b, tail[i + 2] == 5, tail[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw GlassArchiveError.unreadable("its file list is missing") }
        var count = UInt64(le16(tail, eocd + 10))
        var dirSize = UInt64(le32(tail, eocd + 12))
        var dirOffset = UInt64(le32(tail, eocd + 16))
        // ZIP64: the record's locator sits right before the end record.
        if eocd >= 20, le32(tail, eocd - 20) == 0x07064b50 {
            let record = try read(fd, at: le64(tail, eocd - 20 + 8), count: 56)
            guard le32(record, 0) == 0x06064b50 else { throw GlassArchiveError.unreadable("its ZIP64 record is damaged") }
            count = le64(record, 32); dirSize = le64(record, 40); dirOffset = le64(record, 48)
        }
        guard dirOffset + dirSize <= fileSize, dirSize < 1 << 31 else { throw GlassArchiveError.unreadable("its file list is damaged") }
        let dir = try read(fd, at: dirOffset, count: Int(dirSize))
        var entries: [GlassZipEntry] = []
        entries.reserveCapacity(Int(min(count, 1 << 20)))
        var p = 0
        while p + 46 <= dir.count, le32(dir, p) == 0x02014b50 {
            let flags = le16(dir, p + 8), method = le16(dir, p + 10)
            let crc = le32(dir, p + 16)
            var compressed = UInt64(le32(dir, p + 20)), size = UInt64(le32(dir, p + 24))
            let nameLength = Int(le16(dir, p + 28)), extraLength = Int(le16(dir, p + 30)), commentLength = Int(le16(dir, p + 32))
            var offset = UInt64(le32(dir, p + 42))
            guard p + 46 + nameLength + extraLength + commentLength <= dir.count else {
                throw GlassArchiveError.unreadable("its file list is damaged")
            }
            let nameBytes = Array(dir[(p + 46)..<(p + 46 + nameLength)])
            let name = flags & 0x800 != 0 ? String(decoding: nameBytes, as: UTF8.self)
                : (String(bytes: nameBytes, encoding: .utf8) ?? String(bytes: nameBytes, encoding: .isoLatin1) ?? "")
            // ZIP64 sizes live in the extra field, only for the values that overflowed.
            var e = p + 46 + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = le16(dir, e), length = Int(le16(dir, e + 2))
                if id == 1 {
                    var q = e + 4
                    if size == 0xffff_ffff, q + 8 <= extraEnd { size = le64(dir, q); q += 8 }
                    if compressed == 0xffff_ffff, q + 8 <= extraEnd { compressed = le64(dir, q); q += 8 }
                    if offset == 0xffff_ffff, q + 8 <= extraEnd { offset = le64(dir, q); q += 8 }
                }
                e += 4 + length
            }
            entries.append(GlassZipEntry(name: name, method: method, flags: flags, crc: crc,
                                         compressed: compressed, size: size, offset: offset))
            p += 46 + nameLength + extraLength + commentLength
        }
        guard !entries.isEmpty else { throw GlassArchiveError.unreadable("it is empty") }
        return entries
    }

    /// Whether this ZIP can be read here. A ZIP using another method goes to libarchive.
    static func nativelyReadable(_ entries: [GlassZipEntry]) -> Bool {
        entries.allSatisfy { $0.method == 0 || $0.method == 8 }
    }

    /// The highest amount of extra storage extracting needs when the archive shrinks
    /// along the way: files come out last first, each freeing what it took in the archive.
    static func peakExtraBytes(_ entries: [GlassZipEntry]) -> Int64 {
        var extra: Int64 = 0, peak: Int64 = 0
        for entry in entries.sorted(by: { $0.offset > $1.offset }) where !entry.isDirectory {
            let written = extra + Int64(entry.size)
            peak = max(peak, written)
            extra = written - Int64(entry.compressed)
        }
        return peak
    }

    /// Writes one entry to `target`, checks its CRC and flushes it to storage.
    static func extract(_ entry: GlassZipEntry, fd: Int32, to target: URL,
                        progress: (UInt64) -> Void, cancelled: () -> Bool) throws {
        let header = try read(fd, at: entry.offset, count: 30)
        guard le32(header, 0) == 0x04034b50 else { throw GlassArchiveError.damaged(entry.name) }
        let start = entry.offset + 30 + UInt64(le16(header, 26)) + UInt64(le16(header, 28))

        let out = open(target.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard out >= 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
        defer { close(out) }

        var crc = crc32(0, nil, 0)
        var produced: UInt64 = 0
        func write(_ pointer: UnsafePointer<UInt8>, _ count: Int) throws {
            crc = crc32(crc, pointer, uInt(count))
            var done = 0
            while done < count {
                let n = Foundation.write(out, pointer + done, count - done)
                if n < 0, errno == EINTR { continue }
                if n <= 0 {
                    if errno == ENOSPC { throw GlassArchiveError.noSpace(needed: Int64(entry.size), free: 0) }
                    throw GlassArchiveError.unreadable(String(cString: strerror(errno)))
                }
                done += n
            }
            produced += UInt64(count)
        }

        let chunk = 1 << 20
        var input = [UInt8](repeating: 0, count: chunk)
        var output = [UInt8](repeating: 0, count: chunk)
        var position = start, remaining = entry.compressed

        if entry.method == 0 {
            while remaining > 0 {
                if cancelled() { throw GlassArchiveError.cancelled }
                let want = Int(min(UInt64(chunk), remaining))
                let n = input.withUnsafeMutableBytes { pread(fd, $0.baseAddress!, want, off_t(position)) }
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw GlassArchiveError.damaged(entry.name) }
                try input.withUnsafeBufferPointer { try write($0.baseAddress!, n) }
                position += UInt64(n); remaining -= UInt64(n)
                progress(UInt64(n))
            }
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw GlassArchiveError.unreadable("the decompressor would not start")
            }
            defer { inflateEnd(&stream) }
            var ended = false
            while !ended {
                if cancelled() { throw GlassArchiveError.cancelled }
                let want = Int(min(UInt64(chunk), remaining))
                if want == 0 { throw GlassArchiveError.damaged(entry.name) }
                let n = input.withUnsafeMutableBytes { pread(fd, $0.baseAddress!, want, off_t(position)) }
                if n < 0, errno == EINTR { continue }
                guard n > 0 else { throw GlassArchiveError.damaged(entry.name) }
                position += UInt64(n); remaining -= UInt64(n)
                progress(UInt64(n))
                try input.withUnsafeMutableBufferPointer { source in
                    stream.next_in = source.baseAddress
                    stream.avail_in = uInt(n)
                    repeat {
                        let status: Int32 = output.withUnsafeMutableBufferPointer { destination in
                            stream.next_out = destination.baseAddress
                            stream.avail_out = uInt(chunk)
                            return inflate(&stream, Z_NO_FLUSH)
                        }
                        guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                            throw GlassArchiveError.damaged(entry.name)
                        }
                        let made = chunk - Int(stream.avail_out)
                        if made > 0 { try output.withUnsafeBufferPointer { try write($0.baseAddress!, made) } }
                        if status == Z_STREAM_END { ended = true; break }
                    } while stream.avail_out == 0 || stream.avail_in > 0
                }
            }
        }
        guard produced == entry.size, UInt32(truncatingIfNeeded: crc) == entry.crc else {
            throw GlassArchiveError.damaged(entry.name)
        }
        guard fsync(out) == 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
    }

    struct Journal: Codable {
        var destination: String
        var mode: GlassExtractMode
        var entries: [GlassZipEntry]
    }

    static func journalURL(for archive: URL) -> URL { archive.appendingPathExtension("glassjournal") }

    /// Unpacks `archive` into `destination`. Truncating mode shrinks the archive along the
    /// way and deletes it at the end; calling this again after a stop picks up where it was.
    static func unpack(archive: URL, destination: URL, mode: GlassExtractMode,
                       progress: (GlassExtractProgress) -> Void, cancelled: () -> Bool) throws {
        let fm = FileManager.default
        let fd = open(archive.path, O_RDWR)
        guard fd >= 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
        let length = UInt64(info.st_size)

        let journalURL = journalURL(for: archive)
        var entries: [GlassZipEntry]
        if let data = try? Data(contentsOf: journalURL), let journal = try? JSONDecoder().decode(Journal.self, from: data) {
            entries = journal.entries
        } else {
            entries = try directory(fd: fd, size: length)
            if entries.contains(where: { $0.flags & 1 != 0 }) { throw GlassArchiveError.encrypted }
            // The list must be safe on storage before the first truncation removes the archive's own copy.
            let journal = Journal(destination: destination.path, mode: mode, entries: entries)
            try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let files = entries.filter { !$0.isDirectory }.sorted { $0.offset > $1.offset }
        let total = max(1, files.reduce(UInt64(0)) { $0 + $1.compressed })
        var done: UInt64 = 0
        var lastReport = Date.distantPast

        for entry in entries where entry.isDirectory {
            guard let relative = glassSafeRelativePath(entry.name) else { continue }
            try fm.createDirectory(at: destination.appendingPathComponent(relative, isDirectory: true), withIntermediateDirectories: true)
        }
        for entry in files {
            // Beyond the archive's current length: finished before the app stopped.
            if mode == .truncating, entry.offset >= length { done += entry.compressed; continue }
            guard let relative = glassSafeRelativePath(entry.name) else { done += entry.compressed; continue }
            if cancelled() { throw GlassArchiveError.cancelled }
            let target = destination.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = done
            try extract(entry, fd: fd, to: target, progress: { read in
                done += read
                if Date().timeIntervalSince(lastReport) > 0.15 {
                    lastReport = Date()
                    progress(GlassExtractProgress(fraction: Double(done) / Double(total), file: relative))
                }
            }, cancelled: cancelled)
            done = base + entry.compressed
            if mode == .truncating {
                guard ftruncate(fd, off_t(entry.offset)) == 0 else { throw GlassArchiveError.unreadable(String(cString: strerror(errno))) }
            }
        }
        progress(GlassExtractProgress(fraction: 1, file: ""))
        try? fm.removeItem(at: archive)
        try? fm.removeItem(at: journalURL)
    }
}
