// SPDX-License-Identifier: GPL-3.0-or-later
// GameHub: the Library page and its popups, measured from GameHub 6.3.1
// (Android, 844 x 390 dp landscape, the same points as an iPhone's).

import SwiftUI
import UIKit
@preconcurrency import GameController

extension GameHub {
    /// GameHub's side margin, from the screen edge.
    static let margin: CGFloat = 58
    /// The frosted dark plate of GameHub's buttons and tiles over artwork.
    static let glass = Color.white.opacity(0.1)
    static let glassStroke = Color.white.opacity(0.1)
}

/// A frosted card, as GameHub's popups: blur, a grey tint and a hairline edge.
struct GameHubFrost: View {
    var cornerRadius: CGFloat = 24
    var tint = Color(white: 0.2).opacity(0.72)
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tint)
        }
        .overlay(shape.stroke(Color.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
    }
}

/// The focused game's art over the whole screen, darkened from the left where
/// the covers sit. It changes a moment after the row settles, with a crossfade.
struct GameHubLibraryBackdrop: View {
    let entry: LibraryEntry?
    var body: some View {
        ZStack {
            GameHub.background
            if let entry {
                LibraryArtwork(entry: entry, backdrop: true)
                    .id(ConsoleHomeView.key(entry))
                    .transition(.opacity)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.92), location: 0), .init(color: .black.opacity(0.6), location: 0.3),
                                   .init(color: .black.opacity(0.15), location: 0.62), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: .black.opacity(0.55), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.25), value: entry.map(ConsoleHomeView.key))
        .ignoresSafeArea()
    }
}

/// Library: the covers, the title, View Details and ≡, then the four tiles,
/// in one page that scrolls under the fixed top bar.
struct GameHubLibraryPage: View {
    let games: [LibraryEntry]
    let coverIndex: Int
    let tileIndex: Int
    /// 0: the covers have the controller's focus, 1: the tiles.
    let row: Int
    let focusCover: (Int) -> Void
    let details: () -> Void
    let more: (CGRect) -> Void
    let tile: (Int) -> Void

    static let big = CGSize(width: 135, height: 203)
    static let small = CGSize(width: 108, height: 163)
    static let gap: CGFloat = 11
    static var motion: Animation? { UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.33, dampingFraction: 0.95) }

    /// The title and buttons hide while the row moves and come back after it.
    @State private var infoShown = true
    @State private var settle: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !games.isEmpty {
                        covers.id("covers")
                        buttons.padding(.top, 20).opacity(infoShown ? 1 : 0)
                    }
                    GameHubShelves(focus: row == 1 || games.isEmpty ? tileIndex : -1, tap: tile)
                        .padding(.top, games.isEmpty ? 7 : 36).id("tiles")
                }
                .padding(.horizontal, GameHub.margin).padding(.top, 61).padding(.bottom, 30)
            }
            .scrollClipDisabled()
            .onChange(of: row) { _, value in
                withAnimation(Self.motion) { reader.scrollTo(value == 1 ? "tiles" : "covers", anchor: .center) }
            }
        }
        .onChange(of: coverIndex) { _, _ in
            infoShown = false
            settle?.cancel()
            settle = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { infoShown = true }
            }
        }
    }

    /// The row: the selected game at the margin, larger, the ones before it
    /// sliding off to the left past the margin, the title under the next covers.
    private var covers: some View {
        let big = Self.big, small = Self.small, gap = Self.gap
        // The selected cover's left edge sits at the margin.
        let offset = -CGFloat(coverIndex) * (small.width + gap)
        return ZStack(alignment: .topLeading) {
            // An overlay, so the row's full width never sizes the page.
            Color.clear.frame(height: big.height).overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(games.indices, id: \.self) { i in
                        let focused = i == coverIndex
                        cover(games[i], size: focused ? big : small, focused: focused)
                            .onTapGesture { focusCover(i) }
                    }
                }
                .fixedSize()
                .offset(x: offset)
                .animation(Self.motion, value: coverIndex)
            }
            Text(games[coverIndex].title).font(.system(size: 20, weight: .bold)).lineLimit(1)
                .frame(maxWidth: 420, alignment: .leading)
                .offset(x: big.width + gap, y: small.height + 11)
                .opacity(infoShown ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(height: big.height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            let step = value.translation.width < -40 ? 1 : value.translation.width > 40 ? -1 : 0
            let next = min(max(0, coverIndex + step), games.count - 1)
            if step != 0, next != coverIndex { focusCover(next) }
        })
    }

    private func cover(_ entry: LibraryEntry, size: CGSize, focused: Bool) -> some View {
        let controller = GCController.current != nil
        return LibraryArtwork(entry: entry)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused && row == 0 && controller ? Color.white : .clear, lineWidth: 2))
            .overlay(alignment: .bottom) {
                if focused && controller && row == 0 {
                    HStack(spacing: 5) {
                        ConsoleGlyph(text: "A")
                        Text("Launch Game").font(.system(size: 12, weight: .medium))
                    }
                    .padding(.vertical, 6).frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 12, bottomTrailing: 12), style: .continuous))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .contentShape(Rectangle())
            .accessibilityLabel(entry.title)
            .accessibilityAddTraits(.isButton)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: details) {
                Text("View Details").font(.system(size: 17))
                    .frame(width: 155, height: 48)
                    .background(GameHubGlassPlate(cornerRadius: 16))
            }
            .buttonStyle(GameHubPressStyle())
            GeometryReader { geo in
                Button { more(geo.frame(in: .global)) } label: {
                    Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .medium))
                        .frame(width: 48, height: 48)
                        .background(GameHubGlassPlate(cornerRadius: 16))
                }
                .buttonStyle(GameHubPressStyle())
                .accessibilityLabel("More")
            }
            .frame(width: 48, height: 48)
        }
    }
}

/// A translucent plate for buttons and tiles over the artwork.
struct GameHubGlassPlate: View {
    var cornerRadius: CGFloat = 16
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial).opacity(0.55)
            shape.fill(Color(white: 0.16).opacity(0.62))
        }
        .overlay(shape.stroke(GameHub.glassStroke))
        .environment(\.colorScheme, .dark)
    }
}

/// GameHub's buttons dim and shrink a touch while pressed.
struct GameHubPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GameHubShelves: View {
    let focus: Int
    let tap: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(GameHubShelf.allCases) { shelf in
                let focused = focus == shelf.rawValue && GCController.current != nil
                Button { tap(shelf.rawValue) } label: {
                    VStack(spacing: 5) {
                        GameHubShelfIcon(shelf: shelf).frame(width: 33, height: 33)
                        Text(shelf.title).font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 84)
                    .background(GameHubGlassPlate(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(focused ? Color.white.opacity(0.9) : .clear, lineWidth: 2))
                }
                .buttonStyle(GameHubPressStyle())
                .accessibilityLabel(shelf.title)
                .anchorPreference(key: GameHubImportAnchor.self, value: .bounds) { shelf == .importGame ? $0 : nil }
            }
        }
    }
}

// MARK: - Popups

/// What the Library's popups act on.
enum GameHubGameAction {
    case settings, desktop, remove, editInfo, keys
    var title: String {
        switch self {
        case .settings: return "PC Game Settings"
        case .desktop: return "Add to Desktop"
        case .remove: return "Remove Game"
        case .editInfo: return "Edit Info"
        case .keys: return "Keys & Layout"
        }
    }
}

/// ≡'s menu: five rows on a frosted plate, over the dimmed page.
struct GameHubMoreMenu: View {
    let anchor: CGRect
    let choose: (GameHubGameAction) -> Void
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: dismiss)
                VStack(spacing: 0) {
                    let all: [GameHubGameAction] = [.settings, .desktop, .remove, .editInfo, .keys]
                    ForEach(Array(all.enumerated()), id: \.offset) { i, action in
                        Button { choose(action) } label: {
                            Text(action.title).font(.system(size: 17))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 15).frame(height: 41)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < all.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 15) }
                    }
                }
                .padding(.vertical, 1)
                .frame(width: 174)
                .background(GameHubFrost(cornerRadius: 16, tint: Color(white: 0.22).opacity(0.78)))
                .offset(x: anchor.minX + 24 - origin.x, y: max(8, anchor.maxY - 4 - 206 - origin.y))
                .transition(.scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
    }
}

/// GameHub's Notice: a title, a message, Cancel and a blue Confirm. An
/// optional switch sits under the message (Remove Game's "Delete game files").
struct GameHubNotice: View {
    var title = "Notice"
    let message: String
    var option: (String, Binding<Bool>)? = nil
    var confirm = "Confirm"
    let confirmed: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: dismiss)
            VStack(spacing: 0) {
                Text(title).font(.system(size: 18, weight: .bold)).padding(.top, 22)
                Text(message).font(.system(size: 16)).multilineTextAlignment(.center)
                    .padding(.top, 22).padding(.horizontal, 20)
                if let option {
                    Button { option.1.wrappedValue.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.1.wrappedValue ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(option.1.wrappedValue ? GameHub.link : Color.white.opacity(0.5))
                            Text(option.0).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain).padding(.top, 12).padding(.horizontal, 20)
                }
                HStack(spacing: 12) {
                    Button(action: dismiss) {
                        Text("Cancel").font(.system(size: 17)).frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.14)))
                    }
                    Button { dismiss(); confirmed() } label: {
                        Text(confirm).font(.system(size: 17)).frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GameHub.postBlue))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(red: 0.45, green: 0.75, blue: 1).opacity(0.7)))
                    }
                }
                .buttonStyle(GameHubPressStyle())
                .padding(.horizontal, 15).padding(.top, 30).padding(.bottom, 15)
            }
            .frame(width: 333)
            .background(GameHubFrost(cornerRadius: 22, tint: Color(white: 0.17).opacity(0.85)))
            .overlay(alignment: .topTrailing) {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .regular)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).padding(6).accessibilityLabel("Close")
            }
        }
        .foregroundStyle(.white)
    }
}

/// View Details: GameHub's frosted card with the game, its introduction, the
/// More grid and Launch Game. More turns the card into a grid of actions.
struct GameHubDetailsCard: View {
    let entry: LibraryEntry
    let launch: () -> Void
    let choose: (GameHubGameAction) -> Void
    let dismiss: () -> Void
    @State private var grid = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: dismiss)
            ZStack(alignment: .topTrailing) {
                if grid { moreGrid.transition(.opacity) } else { summary.transition(.opacity) }
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).padding(.top, 6).padding(.trailing, 8).accessibilityLabel("Close")
            }
            .frame(width: 415, height: 312)
            .background(GameHubFrost(cornerRadius: 24, tint: Color(white: 0.27).opacity(0.62)))
            .animation(.easeInOut(duration: 0.18), value: grid)
        }
        .foregroundStyle(.white)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                LibraryArtwork(entry: entry).frame(width: 106, height: 106)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title).font(.system(size: 18, weight: .bold)).lineLimit(2)
                    if let size = Self.size(entry) {
                        Text(size).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .padding(.trailing, 40)
            }
            .padding(.top, 50)
            Text("Game Introduction").font(.system(size: 17)).padding(.top, 22)
            Text(Self.introduction(entry)).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1).padding(.top, 4)
            Spacer(minLength: 0)
            HStack(spacing: 15) {
                Button { grid = true } label: {
                    GameHubFourDots().frame(width: 20, height: 20)
                        .frame(width: 51, height: 51)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("More")
                Button { dismiss(); launch() } label: {
                    Text("Launch Game").font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity).frame(height: 51)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GameHub.postBlue))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.45, green: 0.75, blue: 1).opacity(0.6)))
                }
            }
            .buttonStyle(GameHubPressStyle())
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 15)
    }

    private var moreGrid: some View {
        let items: [(GameHubGameAction, String, String)] = [
            (.settings, "PC Engine", "display"),
            (.remove, "Remove from Library", "xmark"),
            (.desktop, "Add to Desktop", "square.grid.2x2"),
            (.editInfo, "Edit Info", "photo"),
            (.keys, "Keys & Layout", "gamecontroller"),
        ]
        return VStack(spacing: 0) {
            Text("More").font(.system(size: 18, weight: .bold)).padding(.top, 26)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 0), count: 4), alignment: .center, spacing: 18) {
                ForEach(items, id: \.1) { item in
                    Button { choose(item.0) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: item.2).font(.system(size: 19))
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                            Text(item.1).font(.system(size: 14)).multilineTextAlignment(.center).lineLimit(2)
                                .frame(height: 36, alignment: .top)
                        }
                        .frame(width: 96)
                    }
                    .buttonStyle(GameHubPressStyle())
                }
            }
            .padding(.top, 26)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    static func introduction(_ entry: LibraryEntry) -> String {
        if entry.steamAppID != nil { return "Steam game" }
        return entry.desktop == true ? "The Windows desktop" : "No description"
    }
    static func size(_ entry: LibraryEntry) -> String? {
        entry.folderBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }
}

/// GameHub's "four dots" mark (the More button and My Games).
struct GameHubFourDots: View {
    var body: some View {
        GeometryReader { geo in
            let d = geo.size.width * 0.42, g = geo.size.width - d * 2
            VStack(spacing: g) {
                HStack(spacing: g) { Circle().stroke(lineWidth: 1.6).frame(width: d, height: d); Circle().stroke(lineWidth: 1.6).frame(width: d, height: d) }
                HStack(spacing: g) { Circle().stroke(lineWidth: 1.6).frame(width: d, height: d); Circle().stroke(lineWidth: 1.6).frame(width: d, height: d) }
            }
        }
    }
}

// MARK: - Removing a game and its files

/// What Remove Game can delete for a game that is not Steam's: the folder
/// Import copied it into (drive_c/Games/<name>), or for a game placed in
/// drive_c by hand its own top folder. System folders and drive_c itself are
/// never touched; Steam games keep their files (Steam manages them).
enum GameFiles {
    private static let system: Set<String> = ["windows", "programdata", "users", "steam", "program files", "program files (x86)"]

    static func target(_ entry: LibraryEntry) -> URL? {
        guard entry.steamAppID == nil, entry.desktop != true else { return nil }
        let parts = entry.relativePath.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }
        let drive = LibraryModel.drive
        if parts.count == 1 { return drive.appendingPathComponent(parts[0]) }          // an .exe at the top of drive_c
        let top = parts[0].lowercased()
        if top == "games" { return drive.appendingPathComponent("Games/" + parts[1]) }   // its folder, or a lone .exe
        if top == "program files" || top == "program files (x86)" {
            return parts.count >= 3 ? drive.appendingPathComponent(parts[0] + "/" + parts[1]) : nil
        }
        if system.contains(top) { return nil }
        return drive.appendingPathComponent(parts[0])
    }

    /// The bytes under `url` (a file or a folder).
    static func size(_ url: URL) -> Int64 {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return 0 }
        if !isFolder.boolValue { return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let file as URL in walk {
                let values = try? file.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
            }
        }
        return total
    }

    /// Removes the game's entry and, with `files`, its folder; other entries
    /// whose program lived in that folder go too. Returns the bytes freed.
    @discardableResult
    static func remove(_ entry: LibraryEntry, files: Bool, model: LibraryModel = .shared) throws -> Int64 {
        var freed: Int64 = 0
        if files, let url = target(entry) {
            freed = size(url)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            let folder = url.path.hasSuffix("/") ? url.path : url.path + "/"
            for other in model.entries where other.id != entry.id && other.steamAppID == nil {
                let path = LibraryModel.drive.appendingPathComponent(other.relativePath).path
                if path.hasPrefix(folder) || path == url.path { model.remove(other.id) }
            }
            LogStore.shared.log("[gamehub-remove] \(entry.title): deleted \(url.lastPathComponent), \(freed) bytes")
        }
        model.remove(entry.id)
        return freed
    }
}

// MARK: - My Games and Steam

/// A Library page behind a tile, as GameHub's My Games: "‹ Title", a tab row
/// with search, settings and sort on the right, then a grid of game cards.
struct GameHubGamesPage<Content: View>: View {
    let title: String
    var tabs: [String] = []
    @Binding var tab: Int
    var sortTitle: String? = "Recently Played"
    var search: (() -> Void)? = nil
    var settings: (() -> Void)? = nil
    let back: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255), Color(red: 22 / 255, green: 22 / 255, blue: 24 / 255),
                                    Color(red: 57 / 255, green: 57 / 255, blue: 57 / 255)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Button(action: back) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                        Text(title).font(.system(size: 24, weight: .bold))
                    }
                    .frame(height: 54).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.leading, 61)
                if !tabs.isEmpty || sortTitle != nil || search != nil {
                    HStack(alignment: .center, spacing: 24) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { i, name in
                            Button { withAnimation(.easeInOut(duration: 0.18)) { tab = i } } label: {
                                VStack(spacing: 5) {
                                    Text(name).font(.system(size: 18, weight: i == tab ? .bold : .regular))
                                        .foregroundStyle(i == tab ? Color.white : Color.white.opacity(0.5))
                                    Capsule().fill(i == tab ? Color.white : .clear).frame(width: 15, height: 3)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            if let search { squareButton("gh-search", "magnifyingglass", search).accessibilityLabel("Search") }
                            if let settings { squareButton("gh-settings-hex", "gearshape", settings).accessibilityLabel("Settings") }
                            if let sortTitle {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.to.line.compact").font(.system(size: 13, weight: .semibold))
                                    Text(sortTitle).font(.system(size: 16))
                                }
                                .padding(.horizontal, 11).frame(height: 31)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.1)))
                            }
                        }
                    }
                    .padding(.leading, 62).padding(.trailing, 58).frame(height: 44)
                }
                content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .foregroundStyle(.white)
    }

    private func squareButton(_ asset: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GHImage(name: asset, fallback: symbol).frame(width: 18, height: 18)
                .frame(width: 31, height: 31)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(GameHubPressStyle())
    }
}

/// GameHub's game card: artwork on top, the name in bold, the GameHub mark and
/// the play time under it.
struct GameHubGameCard: View {
    let entry: LibraryEntry
    var focused = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryArtwork(entry: entry, backdrop: true)
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(4)
            Text(entry.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                .padding(.horizontal, 11).padding(.top, 5)
            HStack(spacing: 5) {
                GHImage(name: "gh-logo-small", fallback: "gamecontroller").frame(width: 15, height: 15).opacity(0.75)
                Text(Self.played(entry)).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 11).padding(.top, 7).padding(.bottom, 12)
        }
        .frame(width: 134)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(focused ? Color.white : Color.white.opacity(0.1), lineWidth: focused ? 2 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Steam's play time for a Steam game, else "--" as GameHub shows it.
    static func played(_ entry: LibraryEntry) -> String {
        if let appID = entry.steamAppID, let summary = SteamOwnedLibrary.shared.playtime[appID]?.summary { return summary }
        return "--"
    }
}

/// The cards in rows from the left, 13 pt apart.
struct GameHubGameGrid: View {
    let games: [LibraryEntry]
    let index: Int
    @Binding var columns: Int
    let tap: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 62 - 58
            let count = max(2, Int((width + 13) / (134 + 13)))
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(134), spacing: 13), count: count), alignment: .leading, spacing: 13) {
                        ForEach(games.indices, id: \.self) { i in
                            GameHubGameCard(entry: games[i], focused: i == index && GCController.current != nil)
                                .onTapGesture { tap(i) }
                                .id(i)
                        }
                    }
                    .padding(.leading, 62).padding(.trailing, 58).padding(.top, 4).padding(.bottom, 30)
                }
                .onChange(of: index) { _, value in withAnimation(ConsoleHomeView.motion) { reader.scrollTo(value, anchor: .center) } }
            }
            .onAppear { columns = count }
            .onChange(of: count) { _, value in columns = value }
        }
    }
}

/// Steam not bound, as GameHub's Steam page shows it.
struct GameHubSteamUnbound: View {
    let bind: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Color(white: 0.45))
                GHImage(name: "gh-entry-steam", fallback: "gearshape.2.fill").frame(width: 50, height: 50).saturation(0).opacity(0.85)
            }
            .frame(width: 46, height: 46)
            Text("Steam data sync\nBind an account to view your personal game library")
                .font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.6)).multilineTextAlignment(.center).lineSpacing(3)
                .padding(.top, 16)
            Button(action: bind) {
                Text("Bind Steam Account").font(.system(size: 17)).padding(.horizontal, 24).frame(height: 48)
                    .background(Capsule().fill(GameHub.postBlue))
                    .overlay(Capsule().stroke(Color(red: 0.45, green: 0.75, blue: 1).opacity(0.6)))
            }
            .buttonStyle(GameHubPressStyle()).padding(.top, 12)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
