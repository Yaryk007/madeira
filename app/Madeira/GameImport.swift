import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// GamehubiOS: Import a game from anywhere the Files app reaches. Pick the
/// game's .exe (then copy its whole folder, or only the file) or the game's
/// folder; the app copies it into drive_c/Games itself and adds it to the
/// library. A pick that is already inside drive_c is added without copying.
///
/// iOS hands an app only what was picked: a picked .exe does not open its
/// folder. To copy the folder, the folder picker opens at that folder and one
/// tap on Open grants it.
@MainActor final class GameImportModel: ObservableObject {
    enum Picker: Identifiable {
        case exe
        case folder(start: URL?, exeName: String?)
        var id: String { if case .exe = self { return "exe" }; return "folder" }
    }
    struct Progress: Equatable { var name: String; var done: Int64; var total: Int64 }

    @Published var menu = false
    @Published var picker: Picker?
    /// A picked .exe outside drive_c, waiting for "whole folder" or "only this file".
    @Published var pendingExe: URL?
    @Published var progress: Progress?
    /// Programs in an imported folder to choose from.
    @Published var choices: [URL] = []
    @Published var error: String?
    private var cancelRequested = false
    var added: (LibraryEntry) -> Void = { _ in }

    static var games: URL { LibraryModel.drive.appendingPathComponent("Games", isDirectory: true) }

    func start() { menu = true }

    // MARK: Picks

    func picked(_ url: URL?, from picker: Picker) {
        guard let url else { return }
        switch picker {
        case .exe:
            if Self.insideDrive(url) { add(url); return }
            pendingExe = url
        case .folder(_, let exeName):
            copy(url, isFolder: true, wantedExe: exeName)
        }
    }

    /// "Copy the whole folder" for the pending .exe: its folder when this app can
    /// already read it, else the folder picker opened there.
    func copyPendingFolder() {
        guard let exe = pendingExe else { return }
        pendingExe = nil
        let folder = exe.deletingLastPathComponent()
        // Readable without a grant (a folder this app may read anyway): copy it.
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil {
            copy(folder, isFolder: true, wantedExe: exe.lastPathComponent)
        } else {
            picker = .folder(start: folder, exeName: exe.lastPathComponent)
        }
    }

    func copyPendingFile() {
        guard let exe = pendingExe else { return }
        pendingExe = nil
        copy(exe, isFolder: false, wantedExe: exe.lastPathComponent)
    }

    func choose(_ exe: URL) {
        choices = []
        add(exe)
    }

    func cancel() { cancelRequested = true }

    // MARK: Copy

    private func copy(_ source: URL, isFolder: Bool, wantedExe: String?) {
        if Self.insideDrive(source) {
            if isFolder { finish(folder: source, wantedExe: wantedExe) } else { add(source) }
            return
        }
        let scoped = source.startAccessingSecurityScopedResource()
        let name = isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        cancelRequested = false
        progress = Progress(name: name, done: 0, total: 0)
        let games = Self.games
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<URL, Error>
            do {
                let destination = try await GameCopier.copy(source, into: games, isFolder: isFolder,
                                                      progress: { [weak self] done, total in
                                                          Task { @MainActor [weak self] in self?.progress = Progress(name: name, done: done, total: total) }
                                                      },
                                                      cancelled: { [weak self] in await MainActor.run { [weak self] in self?.cancelRequested ?? true } })
                result = .success(destination)
            } catch { result = .failure(error) }
            if scoped { source.stopAccessingSecurityScopedResource() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.progress = nil
                switch result {
                case .success(let destination):
                    LogStore.shared.log("[import] copied \(name) into drive_c/Games/\(destination.lastPathComponent)")
                    if isFolder { self.finish(folder: destination, wantedExe: wantedExe) } else { self.add(destination) }
                case .failure(let error):
                    if !(error is CancellationError) { self.error = error.localizedDescription }
                    LogStore.shared.log("[import] \(name) not imported: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    /// The folder is in drive_c: its program is the picked .exe, the only
    /// candidate, or the player's choice.
    private func finish(folder: URL, wantedExe: String?) {
        let programs = GameCopier.programs(in: folder)
        if let wantedExe, let exe = programs.first(where: { $0.lastPathComponent.caseInsensitiveCompare(wantedExe) == .orderedSame }) {
            add(exe)
        } else if programs.count == 1 {
            add(programs[0])
        } else if programs.isEmpty {
            error = "No Windows programs (.exe) were found in \(folder.lastPathComponent). It was copied to drive_c/Games; add its program with Browse drive_c."
        } else {
            choices = programs
        }
    }

    private func add(_ exe: URL) {
        do {
            let entry = try LibraryModel.inspect(exe)
            added(entry)
        } catch { self.error = error.localizedDescription }
    }

    static func insideDrive(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(LibraryModel.drive.path + "/")
    }
}

enum GameCopier {
    struct ImportError: LocalizedError { let errorDescription: String? }

    /// Copies a folder (or one file) into `games` under a free name, reporting
    /// bytes as it goes; large files are copied in chunks so the bar moves and
    /// Cancel applies mid-file. A cancelled copy removes what it wrote.
    static func copy(_ source: URL, into games: URL, isFolder: Bool,
                     progress: @escaping (Int64, Int64) -> Void,
                     cancelled: @escaping () async -> Bool) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: games, withIntermediateDirectories: true)
        let (files, folders) = try contents(of: source, isFolder: isFolder)
        let total = files.reduce(0) { $0 + $1.size }
        if let free = try? games.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < total + 200_000_000 {
            throw ImportError(errorDescription: "Not enough free space: the game needs \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) "
                              + "and \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) is free.")
        }
        let name = isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        var destination = games.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: destination.path) { destination = games.appendingPathComponent("\(name) \(n)", isDirectory: true); n += 1 }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            for folder in folders { try fm.createDirectory(at: destination.appendingPathComponent(folder), withIntermediateDirectories: true) }
            var done: Int64 = 0
            progress(0, total)
            for file in files {
                if await cancelled() { throw CancellationError() }
                let target = destination.appendingPathComponent(file.relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if file.size < 32 << 20 {
                    try fm.copyItem(at: file.url, to: target)
                    done += file.size
                } else {
                    guard fm.createFile(atPath: target.path, contents: nil) else { throw ImportError(errorDescription: "Could not write \(file.relative).") }
                    let input = try FileHandle(forReadingFrom: file.url), output = try FileHandle(forWritingTo: target)
                    defer { try? input.close(); try? output.close() }
                    while let chunk = try input.read(upToCount: 8 << 20), !chunk.isEmpty {
                        if await cancelled() { throw CancellationError() }
                        try output.write(contentsOf: chunk)
                        done += Int64(chunk.count)
                        progress(done, total)
                    }
                }
                progress(done, total)
            }
            return isFolder ? destination : destination.appendingPathComponent(source.lastPathComponent)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    /// What a copy writes: every file (with its size) and folder under `source`,
    /// relative to it; symbolic links are left out.
    private static func contents(of source: URL, isFolder: Bool) throws -> (files: [(url: URL, relative: String, size: Int64)], folders: [String]) {
        guard isFolder else {
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return ([(source, source.lastPathComponent, Int64(size))], [])
        }
        var files: [(url: URL, relative: String, size: Int64)] = []
        var folders: [String] = []
        let base = source.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]) else {
            throw ImportError(errorDescription: "The folder could not be read.")
        }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if values?.isDirectory == true { folders.append(relative) } else { files.append((url, relative, Int64(values?.fileSize ?? 0))) }
        }
        return (files, folders)
    }

    /// The .exe files in a game folder, most likely first: the one named like the
    /// folder, then the largest; installers, uninstallers and helpers last.
    static func programs(in folder: URL) -> [URL] {
        let helpers = ["unins", "setup", "install", "vcredist", "vc_redist", "dxsetup", "dxwebsetup", "crashhandler",
                       "crashreport", "crashpad", "ue4prereq", "dotnet", "redist", "updater", "launcherpatcher"]
        var found: [(url: URL, size: Int, helper: Bool)] = []
        let base = folder.pathComponents.count
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return [] }
        for case let url as URL in walker {
            if url.pathComponents.count - base > 4 { walker.skipDescendants(); continue }
            guard url.pathExtension.lowercased() == "exe" else { continue }
            let lower = url.lastPathComponent.lowercased()
            found.append((url, (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, helpers.contains { lower.contains($0) }))
            if found.count > 200 { break }
        }
        let folderName = GameArtwork.normalized(folder.lastPathComponent)
        return found.sorted { a, b in
            if a.helper != b.helper { return !a.helper }
            let an = GameArtwork.normalized(a.url.deletingPathExtension().lastPathComponent) == folderName
            let bn = GameArtwork.normalized(b.url.deletingPathExtension().lastPathComponent) == folderName
            if an != bn { return an }
            return a.size > b.size
        }.map(\.url)
    }
}

/// The Files app's picker, opening at `directory` when given.
struct GameDocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var directory: URL?
    let picked: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.directoryURL = directory
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let picked: (URL?) -> Void
        init(picked: @escaping (URL?) -> Void) { self.picked = picked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { picked(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { picked(nil) }
    }
}

/// The import flow's sheets and cards, over GameHubHomeView.
struct GameImportOverlay: View {
    @ObservedObject var model: GameImportModel
    let browse: () -> Void

    var body: some View {
        ZStack {
            if model.menu {
                // GameHub's Add Game: a row per source, an icon tile, a title and a line.
                card(title: "Add Game", leading: true, close: { model.menu = false }) {
                    VStack(spacing: 11) {
                        addRow("Local Game", detail: "Choose a local game executable", icon: "plus") {
                            model.menu = false; model.picker = .exe
                        }
                        addRow("Game Folder", detail: "Choose a game folder; GameHub copies it in", icon: "folder") {
                            model.menu = false; model.picker = .folder(start: nil, exeName: nil)
                        }
                        addRow("drive_c", detail: "Add a program already in GameHub's drive C", icon: "internaldrive") {
                            model.menu = false; browse()
                        }
                    }
                }
            } else if let exe = model.pendingExe {
                card(title: "Import \(exe.lastPathComponent)", close: { model.pendingExe = nil }) {
                    VStack(spacing: 12) {
                        wide("Copy the whole folder", detail: "Recommended: the game's files next to \(exe.lastPathComponent) come along.",
                             icon: "folder", primary: true, action: model.copyPendingFolder)
                        wide("Copy only this file", detail: "For a program that needs nothing else.", icon: "doc", primary: false,
                             action: model.copyPendingFile)
                    }
                }
            } else if let progress = model.progress {
                card(title: "Importing \(progress.name)", close: nil) {
                    VStack(spacing: 12) {
                        ProgressView(value: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0).tint(GameHub.link)
                        Text(progress.total > 0
                             ? "\(ByteCountFormatter.string(fromByteCount: progress.done, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file))"
                             : "Preparing…")
                            .font(.system(size: 14).monospacedDigit()).foregroundStyle(GameHub.secondary)
                        Button("Cancel", action: model.cancel).font(.system(size: 16)).padding(.top, 4)
                    }
                    .frame(width: 340)
                }
            } else if !model.choices.isEmpty {
                card(title: "Choose the game's program", close: { model.choices = [] }) {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.choices, id: \.path) { exe in
                                Button { model.choose(exe) } label: {
                                    HStack {
                                        Image(systemName: "app.dashed")
                                        Text(exe.lastPathComponent).lineLimit(1)
                                        Spacer()
                                        Text(ByteCountFormatter.string(fromByteCount: Int64((try? exe.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file))
                                            .foregroundStyle(GameHub.secondary)
                                    }
                                    .font(.system(size: 15)).padding(.horizontal, 14).frame(height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(width: 420).frame(maxHeight: 230)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.menu)
        .animation(.easeInOut(duration: 0.15), value: model.progress == nil)
        .sheet(item: $model.picker) { picker in
            switch picker {
            case .exe:
                GameDocumentPicker(types: [.exe, UTType(filenameExtension: "exe") ?? .data]) { model.picked($0, from: picker) }
            case .folder(let start, _):
                GameDocumentPicker(types: [.folder], directory: start) { model.picked($0, from: picker) }
            }
        }
        .alert("Import", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func card<Content: View>(title: String, leading: Bool = false, close: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { close?() }
            VStack(alignment: leading ? .leading : .center, spacing: leading ? 16 : 18) {
                Text(title).font(.system(size: leading ? 20 : 19, weight: leading ? .bold : .medium)).lineLimit(1)
                    .padding(.trailing, 30).padding(.leading, leading ? 0 : 30)
                content()
            }
            .padding(.horizontal, leading ? 15 : 24).padding(.top, leading ? 18 : 22).padding(.bottom, leading ? 15 : 22)
            .background(GameHubFrost(cornerRadius: 22, tint: Color(white: 0.17).opacity(0.85)))
            .overlay(alignment: .topTrailing) {
                if let close {
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 16, weight: .light)).padding(16) }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }
            }
        }
        .transition(.opacity)
    }

    private func addRow(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .bold))
                    Text(detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(width: 303, height: 70)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.1)))
        }
        .buttonStyle(GameHubPressStyle())
    }

    private func option(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 30)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.5))
                Text(title).font(.system(size: 15))
            }
            .frame(width: 130, height: 110)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func wide(_ title: String, detail: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 22)).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .medium))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).frame(width: 400, height: 64)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(primary ? AnyShapeStyle(GameHub.postBlue) : AnyShapeStyle(Color.white.opacity(0.07))))
        }
        .buttonStyle(.plain)
    }
}
