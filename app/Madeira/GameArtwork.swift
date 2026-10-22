import SwiftUI
import UIKit

/// GamehubiOS: artwork for every game. A game you added gets Steam's store
/// artwork when its title matches a Steam app closely enough and Steam has a
/// library cover for it; otherwise it shows the largest icon in its .exe. A
/// cover you chose and a Steam game's own artwork always come first. The lookup
/// runs once per game (LibraryEntry.artworkChecked); Game details' Find on
/// Steam and cover picker still override it.
enum GameArtwork {
    static let revision = 1
    static var folder: URL { LibraryModel.documents.appendingPathComponent("madeira-art", isDirectory: true) }
    @MainActor private static var inFlight = Set<UUID>()
    private static let cache = NSCache<NSString, UIImage>()

    static func needsLookup(_ entry: LibraryEntry) -> Bool {
        entry.desktop != true && entry.steamAppID == nil && entry.coverFile == nil && (entry.artworkChecked ?? 0) < revision
    }

    static func icon(_ entry: LibraryEntry) -> UIImage? {
        guard let name = entry.iconFile else { return nil }
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let image = UIImage(contentsOfFile: folder.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// The lookup for one library entry; saves what it found on the entry.
    @MainActor static func resolve(_ id: UUID) async {
        let model = LibraryModel.shared
        guard !inFlight.contains(id), let entry = model.entries.first(where: { $0.id == id }), needsLookup(entry) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        let exe = try? LibraryModel.executable(entry.launchRelativePath)
        let iconName = entry.id.uuidString + "-icon.png"
        let dir = folder
        let icon: String? = await Task.detached(priority: .utility) { () -> String? in
            guard let exe, exe.pathExtension.lowercased() == "exe", let png = PEIcon.png(exe) else { return nil }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return (try? png.write(to: dir.appendingPathComponent(iconName), options: .atomic)) == nil ? nil : iconName
        }.value
        var steamID = entry.steamID
        if steamID == nil {
            let exeName = exe?.deletingPathExtension().lastPathComponent
            steamID = await match(title: entry.title, exeName: exeName)
        }
        guard var updated = model.entries.first(where: { $0.id == id }), updated.coverFile == nil else { return }
        if updated.steamID == nil, let steamID { updated.steamID = steamID }
        if let icon { updated.iconFile = icon; cache.removeObject(forKey: icon as NSString) }
        updated.artworkChecked = revision
        model.save(updated)
        LogStore.shared.log("[artwork] \(updated.title): steam=\(updated.steamID.map(String.init) ?? "none") icon=\(icon == nil ? 0 : 1)")
    }

    /// A Steam app whose name is the title (or the program's name) once both are
    /// reduced to letters and digits, or nearly so, and which has a library cover.
    static func match(title: String, exeName: String?) async -> Int? {
        for query in [title, exeName].compactMap({ $0 }).map(clean).filter({ $0.count >= 2 }) {
            guard let results = try? await SteamCatalog.search(query) else { continue }
            let wanted = normalized(query)
            for result in results.prefix(8) {
                let name = normalized(result.name)
                let close = name == wanted
                    || (min(name.count, wanted.count) >= 4 && (name.hasPrefix(wanted) || wanted.hasPrefix(name))
                        && Double(min(name.count, wanted.count)) / Double(max(name.count, wanted.count)) >= 0.7)
                if close, await hasCover(result.id) { return result.id }
            }
        }
        return nil
    }

    /// A title as a search term: no file extension, separators as spaces, and
    /// without installer and platform words or version numbers.
    static func clean(_ text: String) -> String {
        var s = text
        if let dot = s.lastIndex(of: "."), ["exe", "bat", "cmd"].contains(s[s.index(after: dot)...].lowercased()) { s = String(s[..<dot]) }
        s = s.replacingOccurrences(of: "[_\\-.]+", with: " ", options: .regularExpression)
        let drop: Set<String> = ["setup", "installer", "install", "launcher", "x64", "x86", "win64", "win32", "64bit", "32bit",
                                 "dx11", "dx12", "shipping", "release", "portable", "gog", "repack"]
        let words = s.split(separator: " ").map(String.init).filter { word in
            let lower = word.lowercased()
            return !drop.contains(lower) && lower.range(of: "^v?\\d+(\\.\\d+)*$", options: .regularExpression) == nil
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(String.init).joined()
    }

    private static func hasCover(_ id: Int) async -> Bool {
        guard let url = SteamCatalog.cover(id) else { return false }
        var request = URLRequest(url: url); request.httpMethod = "HEAD"; request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

/// The program's icon as artwork: blurred behind, the icon itself in the middle
/// (only the blur on a backdrop), as GameHub draws a game without art.
struct GameIconArtwork: View {
    let image: UIImage
    var backdrop = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: min(geo.size.width, geo.size.height) * 0.12)
                    .overlay(Color.black.opacity(backdrop ? 0.15 : 0.25))
                if !backdrop {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: min(geo.size.width, geo.size.height) * 0.62)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height).clipped()
        }
    }
}

/// The largest icon in a Windows program (its first RT_GROUP_ICON), as PNG.
/// Reads only the PE headers and the resource section of a mapped file.
enum PEIcon {
    static func png(_ url: URL) -> Data? {
        guard let ico = largestICO(url), let image = UIImage(data: ico), image.size.width >= 16 else { return nil }
        return image.pngData()
    }

    /// The group's largest image, wrapped as a one-image .ico file (ImageIO
    /// decodes both its PNG and its BMP forms).
    static func largestICO(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count > 0x40 else { return nil }
        let base = data.startIndex
        func u8(_ o: Int) -> Int? { o >= 0 && o < data.count ? Int(data[base + o]) : nil }
        func u16(_ o: Int) -> Int? { guard let a = u8(o), let b = u8(o + 1) else { return nil }; return a | b << 8 }
        func u32(_ o: Int) -> Int? { guard let a = u16(o), let b = u16(o + 2) else { return nil }; return a | b << 16 }

        guard u16(0) == 0x5A4D, let pe = u32(0x3C), u32(pe) == 0x4550 else { return nil }
        let coff = pe + 4
        guard let sectionCount = u16(coff + 2), let optionalSize = u16(coff + 16) else { return nil }
        let optional = coff + 20
        guard let magic = u16(optional) else { return nil }
        let directories = optional + (magic == 0x20B ? 112 : 96)
        guard let resourceRVA = u32(directories + 2 * 8), resourceRVA != 0 else { return nil }
        var sections: [(va: Int, size: Int, raw: Int)] = []
        for i in 0..<min(sectionCount, 96) {
            let s = optional + optionalSize + i * 40
            guard let virtualSize = u32(s + 8), let va = u32(s + 12), let rawSize = u32(s + 16), let raw = u32(s + 20) else { return nil }
            sections.append((va, max(virtualSize, rawSize), raw))
        }
        func offset(_ rva: Int) -> Int? {
            sections.first { rva >= $0.va && rva < $0.va + $0.size }.map { rva - $0.va + $0.raw }
        }
        guard let root = offset(resourceRVA) else { return nil }

        struct Entry { let id: Int?; let target: Int; let directory: Bool }
        func entries(_ dir: Int) -> [Entry] {
            guard let named = u16(dir + 12), let ids = u16(dir + 14) else { return [] }
            return (0..<min(named + ids, 4096)).compactMap { i in
                let e = dir + 16 + i * 8
                guard let name = u32(e), let off = u32(e + 4) else { return nil }
                return Entry(id: name & 0x8000_0000 != 0 ? nil : name, target: root + (off & 0x7FFF_FFFF), directory: off & 0x8000_0000 != 0)
            }
        }
        /// The first data entry under `entry` (a name or ID, then a language).
        func leaf(_ entry: Entry, depth: Int = 0) -> (offset: Int, size: Int)? {
            if entry.directory {
                guard depth < 3, let first = entries(entry.target).first else { return nil }
                return leaf(first, depth: depth + 1)
            }
            guard let rva = u32(entry.target), let size = u32(entry.target + 4), let at = offset(rva), at + size <= data.count else { return nil }
            return (at, size)
        }

        let types = entries(root)
        guard let groups = types.first(where: { $0.id == 14 }), let icons = types.first(where: { $0.id == 3 }),
              let group = entries(groups.target).first, let dir = leaf(group), let count = u16(dir.offset + 4) else { return nil }
        // GRPICONDIRENTRY: width, height (0 = 256), colours, reserved, planes, bit count, bytes, ID.
        var best: (index: Int, score: Int)?
        for i in 0..<min(count, 64) {
            let e = dir.offset + 6 + i * 14
            guard let w = u8(e), let h = u8(e + 1), let bits = u16(e + 6) else { break }
            let score = (w == 0 ? 256 : w) * (h == 0 ? 256 : h) * 64 + bits
            if best == nil || score > best!.score { best = (i, score) }
        }
        guard let pick = best else { return nil }
        let e = dir.offset + 6 + pick.index * 14
        guard let id = u16(e + 12), let iconEntry = entries(icons.target).first(where: { $0.id == id }),
              let image = leaf(iconEntry), image.size > 0, image.size < 16 << 20 else { return nil }

        var ico = Data([0, 0, 1, 0, 1, 0])
        ico.append(contentsOf: (0..<8).map { data[base + e + $0] })        // width ... bit count
        var size = UInt32(image.size).littleEndian, at = UInt32(22).littleEndian
        withUnsafeBytes(of: &size) { ico.append(contentsOf: $0) }
        withUnsafeBytes(of: &at) { ico.append(contentsOf: $0) }
        ico.append(data[(base + image.offset)..<(base + image.offset + image.size)])
        return ico
    }
}
