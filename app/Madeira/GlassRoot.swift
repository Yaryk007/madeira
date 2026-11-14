// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Glass: the home interface, built to the design prototype (docs/design/madeira-prototype.dc.html):
// the same sizes, spacing, curves and timings, landscape, and every part of it works from a controller.
// Boot screen, "Who's playing?", quick menu and the controls it shares live in GlassOS.swift.
// Library.swift's LibraryView stays as "All settings", and its detail pages open as sheets.

import SwiftUI
import GameController
import UniformTypeIdentifiers

// MARK: - Surfaces

enum GlassUI {
    static let key = "madeiraGlassInterface"
    /// Settings › Interface, or env.MADEIRA_GLASS = 0 in madeira.cfg, go back to the classic library.
    static var enabled: Bool {
        if UserDefaults.standard.object(forKey: key) != nil { return UserDefaults.standard.bool(forKey: key) }
        return MadeiraConfig.flag("MADEIRA_GLASS")
    }
}

/// Settings › Appearance › Surfaces: the prototype's clear glass by default, with the earlier looks kept as choices.
enum GlassStyle: String, CaseIterable {
    case liquid = "Liquid Glass", current = "Current glass", frosted = "Frosted", black = "Black"
    static let key = "madeiraGlassStyle"
    static var chosen: GlassStyle { GlassStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .liquid }
}

extension View {
    /// Every Glass surface. Liquid Glass is clear glass with a lit top edge, as in the prototype; Current glass is the
    /// regular system glass the first Glass builds used; Frosted is the prototype's frosted stand-in; Black is flat.
    @ViewBuilder func glassSurface(radius: CGFloat, interactive: Bool = false, tint: Color? = nil) -> some View {
        let style = GlassStyle.chosen
        let shape = RoundedRectangle(cornerRadius: style == .black ? min(radius, 6) : radius, style: .continuous)
        switch style {
        case .black:
            self.background(Color.black, in: shape).overlay(shape.stroke(Color(red: 0.2, green: 0.2, blue: 0.227), lineWidth: 1))
        case .frosted:
            self.background(Color(red: 20 / 255, green: 20 / 255, blue: 26 / 255).opacity(0.6), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
        case .liquid, .current:
            if #available(iOS 26.0, *) {
                let base = style == .liquid ? Glass.clear : Glass.regular
                let glass = tint.map { base.tint($0) } ?? base
                self.glassEffect(glass.interactive(interactive), in: shape)
                    .overlay {
                        if style == .liquid {
                            // The prototype's lit top edge and faint lower rim.
                            shape.stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .shadow(color: .black.opacity(style == .liquid ? 0.26 : 0), radius: 15, y: 10)
            } else {
                self.background(Color.white.opacity(0.07), in: shape)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
            }
        }
    }
}

/// The PS5's shine: a soft band of light sweeps across the selected cover every 2.4 s
/// (the prototype's `shine`: across in the first 55% on cubic-bezier(0.45, 0, 0.2, 1), then rest).
struct GlassShine: View {
    var radius: CGFloat = 12
    private static let curve = GlassBezier(x1: 0.45, y1: 0, x2: 0.2, y2: 1)
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                let eased = Self.curve(min(1, t / 0.55))
                let x = (-0.7 + 2 * eased) * geo.size.width
                LinearGradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.07), location: 0.3),
                                       .init(color: .white.opacity(0.4), location: 0.5), .init(color: .white.opacity(0.07), location: 0.7),
                                       .init(color: .white.opacity(0), location: 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5, height: geo.size.height * 1.4)
                    .rotationEffect(.degrees(14))
                    .offset(x: x, y: -geo.size.height * 0.2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(alignment: .top) {
            // shine::after: a lit top edge and a faint rim.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.12), .white.opacity(0.12)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The prototype's two buttons: `primary` (white, dark text, bold) and `secondary` (glass), both 44 high.
/// `compact` is the home page's 13-point pair; `tinted` is the plain 12% white fill used inside sheets.
struct GlassButtonStyle: ButtonStyle {
    var compact = false
    var primary = false
    var selected = false
    var tinted = false
    var wide = false
    func makeBody(configuration: Configuration) -> some View {
        let filled = primary || selected
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: filled ? .bold : .semibold))
            .lineLimit(1)
            .foregroundStyle(filled ? GlassOS.ink : Color.white)
            .padding(.horizontal, filled ? (compact ? 18 : 24) : (compact ? 14 : 20))
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 44)
            .background {
                if filled { Capsule().fill(.white) } else if tinted { Capsule().fill(.white.opacity(0.12)) }
            }
            .modifier(GlassButtonSurface(on: !filled && !tinted))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(GlassMotion.css(0.15), value: configuration.isPressed)
    }
}
private struct GlassButtonSurface: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.glassSurface(radius: 22, interactive: true) } else { content }
    }
}

/// Where the controller is: the prototype's focus outline, 2 points of white just outside the shape.
struct GlassFocusRing: View {
    var radius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: radius + 3, style: .continuous).stroke(.white, lineWidth: 2)
            .padding(-3).allowsHitTesting(false)
    }
}

/// The round close button of the sheets.
struct GlassCloseButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.9))
        .accessibilityLabel("Close")
    }
}

// MARK: - Games

struct GlassGame: Identifiable {
    enum Source: String { case steam = "Steam", epic = "Epic", gog = "GOG", imported = "Imported" }
    var id: String
    var title: String
    var source: Source
    var covers: [URL] = []
    var hero: URL?
    var entry: LibraryEntry?
    var steamID: Int?
    var storeKey: String?
    var progress: Double?
    var transfer: String?
    var lastPlayed: Date?
    var installed: Bool { entry != nil }
    var status: String {
        if let transfer { return transfer }
        return installed ? "Ready to play" : "Not installed"
    }
    var subtitle: String { source.rawValue + " · " + status }
}

/// A game's art: its own cover, then each URL in turn.
struct GlassCover: View {
    let game: GlassGame
    @State private var index = 0
    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            Text(String(game.title.prefix(1))).font(.system(size: 30, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            if let entry = game.entry, entry.coverFile != nil || entry.steamID != nil || entry.steamAppID != nil {
                LibraryArtwork(entry: entry)
            } else if index < game.covers.count {
                AsyncImage(url: game.covers[index]) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Color.clear.onAppear { index += 1 }
                    default: Color.clear
                    }
                }
            }
        }.clipped()
    }
}

/// The screen-filling art behind everything. A new game's art fades in over 0.45 s while
/// settling from 105% over 0.9 s, as the prototype's `.bg` does; the old one fades out.
struct GlassBackdrop: View {
    let game: GlassGame?
    var body: some View {
        GeometryReader { geo in
            ZStack {
                GlassOS.night
                if let game {
                    GlassBackdropArt(game: game)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                        .id(game.id)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(GlassMotion.css(0.45))))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct GlassBackdropArt: View {
    let game: GlassGame
    @State private var shown = false
    @State private var settled = false
    var body: some View {
        Group {
            if let hero = game.hero {
                AsyncImage(url: hero) { image in image.resizable().scaledToFill() } placeholder: { GlassCover(game: game).blur(radius: 24) }
            } else if let entry = game.entry, entry.steamID != nil || entry.steamAppID != nil {
                LibraryArtwork(entry: entry, backdrop: true)
            } else {
                GlassCover(game: game).blur(radius: 24).opacity(0.85)
            }
        }
        .scaleEffect(settled ? 1 : 1.05)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(GlassMotion.css(0.45)) { shown = true }
            withAnimation(GlassMotion.reduced ? nil : GlassMotion.open(0.9)) { settled = true }
        }
    }
}

// MARK: - Rows

struct GlassRow: Identifiable {
    enum Kind {
        case toggle(Bool, (Bool) -> Void)
        case choice([String], Int, (Int) -> Void)
        case info(String)
        case action(String?, () -> Void)
        case slider(Double, ClosedRange<Double>, (Double) -> Void)
        case custom(AnyView)
    }
    var id: String { title }
    var title: String
    var detail: String?
    var kind: Kind

    /// A choice too wide to sit beside its label goes under it.
    var stacks: Bool {
        switch kind {
        case .choice(let options, _, _): return options.count > 3 || options.joined().count > 24
        case .custom: return true
        default: return false
        }
    }
}

/// A settings row as the prototype draws it: label and detail on the left, the control on the
/// right, a hairline under every row but the last.
struct GlassRowView: View {
    let row: GlassRow
    let focused: Bool
    var last = false
    var body: some View {
        Group {
            if row.stacks {
                VStack(alignment: .leading, spacing: 8) {
                    labels
                    control
                }
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 14) {
                    labels.frame(maxWidth: .infinity, alignment: .leading)
                    control
                }
                .padding(.vertical, 7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background {
            if focused { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.1)).padding(.horizontal, -8) }
        }
        .overlay {
            if focused { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 1.5).padding(.horizontal, -8) }
        }
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title).font(.system(size: 15, weight: .medium))
            if let detail = row.detail {
                Text(detail).font(.system(size: 12)).lineSpacing(2).foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch row.kind {
        case .toggle(let on, let change):
            GlassSwitch(on: on, label: row.title) { change(!on) }
        case .choice(let options, let selected, let pick):
            GlassSegment(options: options, selected: selected, padding: options.count > 4 ? 11 : 15, pick: pick).fixedSize()
        case .info(let value):
            Text(value).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
        case .action(let label, let run):
            Button(action: run) {
                HStack(spacing: 4) {
                    if let label { Text(label).font(.system(size: 14)).lineLimit(1) }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }.foregroundStyle(.white.opacity(0.8)).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        case .slider(let value, let range, let change):
            Slider(value: Binding(get: { value }, set: change), in: range).tint(.white).frame(width: 150)
        case .custom(let view):
            view
        }
    }
}

extension GlassRow {
    /// The controller's accept and left/right on a row.
    func accept() {
        switch kind {
        case .toggle(let on, let change): change(!on)
        case .choice(let options, let selected, let pick): pick((selected + 1) % options.count)
        case .action(_, let run): run()
        case .info, .slider, .custom: break
        }
    }
    func step(_ delta: Int) {
        switch kind {
        case .choice(let options, let selected, let pick):
            let next = selected + delta
            if options.indices.contains(next) { pick(next) }
        case .slider(let value, let range, let change):
            let step = (range.upperBound - range.lowerBound) / 20
            change(min(range.upperBound, max(range.lowerBound, value + Double(delta) * step)))
        default: break
        }
    }
    var steps: Bool {
        switch kind {
        case .choice, .slider: return true
        default: return false
        }
    }
}

/// The prototype's list of rows, with its hairlines and the controller's row.
struct GlassRowList: View {
    let rows: [GlassRow]
    var focus = -1
    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            GlassRowView(row: row, focused: focus == index, last: index == rows.count - 1).id(index)
        }
    }
}

// MARK: - Root

enum GlassTab: String, CaseIterable, Identifiable {
    case home = "Home", library = "Library", store = "Store", settings = "Settings"
    var id: String { rawValue }
}

enum GlassOverlay: Equatable {
    case details(String), search, downloads, importer, storeItem(String), controllerTest, quick
}

enum GlassSheet: Identifiable {
    case signIn(GlassStoreKind), web(String, URL), gameSettings(LibraryEntry), classicSettings, jit, files
    var id: String {
        switch self {
        case .signIn(let kind): return "sign-in" + kind.rawValue
        case .web(_, let url): return url.absoluteString
        case .gameSettings(let entry): return entry.id.uuidString
        case .classicSettings: return "classic"
        case .jit: return "jit"
        case .files: return "files"
        }
    }
}

@MainActor final class GlassGameCache {
    static let shared = GlassGameCache()
    var signature = ""
    var games: [GlassGame] = []
}

struct GlassRootView: View {
    var play: (LibraryEntry) -> Void
    var enableJIT: () -> Void
    var startDock: (DockGame, Bool) -> Void

    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var steam = SteamOwnedLibrary.shared
    @ObservedObject private var steamGames = SteamGamesModel.shared
    @ObservedObject private var epic = EpicLibrary.shared
    @ObservedObject private var gog = GOGLibrary.shared
    @ObservedObject private var importer = GlassImporter.shared
    @ObservedObject private var pads = GlassPads.shared
    @ObservedObject private var onboarding = OnboardingModel.shared
    @ObservedObject private var jitState = LibraryJITState.shared
    @ObservedObject private var shell = GlassShell.shared
    @ObservedObject private var profiles = GlassProfiles.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab = GlassTab.home
    @State private var overlay: GlassOverlay?
    @State private var sheet: GlassSheet?
    @State private var selectedID: String?
    /// Where the controller is on the home page: 0 top bar, 1 covers, 2 Play and Details.
    @State private var homeZone = 1
    @State private var homeButton = 0
    /// The top bar's buttons: Search, Downloads, the profile (quick menu).
    @State private var topButton = 0
    @State private var libraryFilter = 0
    @State private var libraryFocus = 0
    @State private var libraryZone = 1
    @State private var store = GlassStoreKind.steam
    @State private var shelves: [GlassStoreShelf] = []
    @State private var storeResults: [GlassStoreItem]?
    @State private var storeLoading = false
    @State private var storeFocus = (shelf: -1, item: 0)
    @State private var storeItem: GlassStoreItem?
    @State private var storeDetails: GlassStoreDetails?
    @State private var storeQuery = ""
    @State private var searchText = ""
    @State private var searchFocus = 0
    @State private var settingsCategory = 2
    @State private var settingsFocus = -1
    @State private var overlayFocus = 0
    @State private var opening: (game: GlassGame, frame: CGRect)?
    @State private var openingGrown = false
    @State private var openingHero = false
    @State private var selectedFrame = CGRect.zero
    @State private var picking = false
    @State private var revision = 0
    @State private var toast: String?
    @State private var toastRun = 0
    @State private var renaming: GlassProfile?
    @State private var renameText = ""

    /// Built once per change: the body reads it many times, and Steam's list can be long.
    private var games: [GlassGame] {
        let signature = [model.revision, steam.owned.count, steamGames.games.count, epic.owned.count, epic.installed.count,
                         gog.owned.count, gog.installed.count, steam.downloads.count, epic.downloads.count, gog.downloads.count]
            .map(String.init).joined(separator: ",") + transferSignature
        if signature == GlassGameCache.shared.signature { return GlassGameCache.shared.games }
        let built = buildGames()
        GlassGameCache.shared.signature = signature
        GlassGameCache.shared.games = built
        return built
    }

    private var transferSignature: String {
        let steamBytes = steam.downloads.values.map { "\($0.progress.doneBytes)\($0.state)" }.joined()
        let epicBytes = epic.downloads.values.map { "\($0.progress.doneBytes)\($0.state)" }.joined()
        let gogBytes = gog.downloads.values.map { "\($0.progress.doneBytes)\($0.state)" }.joined()
        return steamBytes + epicBytes + gogBytes
    }

    private func buildGames() -> [GlassGame] {
        var list: [GlassGame] = []
        for entry in model.entries where entry.desktop != true && entry.listedInLibrary
            && entry.steamAppID == nil && entry.epicAppName == nil && entry.gogProductID == nil {
            list.append(GlassGame(id: entry.id.uuidString, title: entry.title, source: .imported, entry: entry, lastPlayed: entry.lastPlayed))
        }
        let owned = SteamOwnedLibrary.enabled ? steam.owned : []
        for item in SteamGamesRules.items(installed: steamGames.games, owned: owned, search: "") {
            var game = GlassGame(id: "steam\(item.id)", title: item.name, source: .steam,
                                 covers: SteamGamesRules.artwork(appID: item.id) { steam.game($0) },
                                 hero: SteamCatalog.hero(item.id), steamID: item.id)
            if let installed = item.installed {
                game.entry = model.steamEntry(installed, title: item.name)
                game.lastPlayed = game.entry?.lastPlayed
            }
            if let download = steam.downloads[item.id] {
                let total = download.progress.totalBytes
                game.progress = total > 0 ? Double(download.progress.doneBytes) / Double(total) : 0
                game.transfer = transferText(game.progress ?? 0, paused: download.state == .paused)
            }
            list.append(game)
        }
        if EpicLibrary.enabled {
            for item in EpicGamesRules.items(epic, search: "") {
                var game = GlassGame(id: "epic" + item.id, title: item.title, source: .epic, covers: item.cover.map { [$0] } ?? [],
                                     hero: item.owned?.wide, storeKey: item.id)
                if let installed = item.installed { game.entry = model.epicEntry(installed); game.lastPlayed = game.entry?.lastPlayed }
                if let download = epic.downloads[item.id] {
                    game.progress = download.progress.fraction
                    game.transfer = transferText(download.progress.fraction, paused: download.state == .paused)
                }
                list.append(game)
            }
        }
        if GOGLibrary.enabled {
            for item in GOGGamesRules.items(gog, search: "") {
                var game = GlassGame(id: "gog" + item.id, title: item.title, source: .gog, covers: item.cover.map { [$0] } ?? [], storeKey: item.id)
                if let installed = item.installed { game.entry = model.gogEntry(installed); game.lastPlayed = game.entry?.lastPlayed }
                if let download = gog.downloads[item.id] {
                    let total = download.progress.totalBytes
                    let fraction = total > 0 ? Double(download.progress.doneBytes) / Double(total) : 0
                    game.progress = fraction
                    game.transfer = transferText(fraction, paused: download.state == .paused)
                }
                list.append(game)
            }
        }
        return list.sorted { a, b in
            if a.installed != b.installed { return a.installed }
            if a.lastPlayed != b.lastPlayed { return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast) }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private func transferText(_ fraction: Double, paused: Bool) -> String {
        paused ? "Paused" : "Downloading \(Int(fraction * 100))%"
    }


    /// The prototype's 44-point side margin, whatever the notch's safe area says.
    private let sidePadding: CGFloat = 44

    private var homeGames: [GlassGame] { Array(games.prefix(6)) }
    private var selected: GlassGame? {
        let list = games
        return list.first { $0.id == selectedID } ?? list.first
    }
    private static let filters = ["All", "Steam", "Epic", "GOG", "Imported"]
    private var libraryGames: [GlassGame] {
        let filter = Self.filters[libraryFilter]
        return filter == "All" ? games : games.filter { $0.source.rawValue == filter }
    }

    var body: some View {
        ZStack {
            GlassBackdrop(game: selected)
            switch shell.stage {
            case .home:
                homeShell
            case .welcome:
                GlassWelcome().transition(.opacity)
            case .boot:
                GlassBootScreen(finished: { shell.bootFinished() }).id(shell.bootRun).transition(.identity)
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $onboarding.presented) { OnboardingView() }
        .sheet(item: $sheet, onDismiss: sheetClosed) { sheetView($0) }
        .fileImporter(isPresented: $picking, allowedContentTypes: GlassImporter.pickerTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                urls.forEach { importer.start($0, scoped: true) }
                if !urls.isEmpty { show(toast: urls.count == 1 ? "Importing \(urls[0].lastPathComponent)" : "Importing \(urls.count) items") }
            }
            overlay = .downloads
        }
        .alert("Madeira", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            if !jitState.enabled { Button("Enable JIT") { model.error = nil; enableJIT() } }
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Unpack without a spare copy?", isPresented: Binding(get: { importer.approval != nil }, set: { _ in })) {
            Button("Unpack and free the archive", role: .destructive) { importer.answer(approve: true) }
            Button("Cancel", role: .cancel) { importer.answer(approve: false) }
        } message: {
            Text("There isn't room for this RAR and the game at once, so Madeira will free the archive as it unpacks. Keep the app open. If it stops partway, the archive can't be used again and you'd need a new copy." + (pads.pads.isEmpty ? "" : (pads.family == .playStation ? "\n\n✕ continues, ○ cancels." : "\n\nA continues, B cancels.")))
        }
        .alert("Profile name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let renaming { profiles.rename(renaming.id, to: renameText) }; renaming = nil; revision += 1 }
            if profiles.list.count > 1 {
                Button("Remove profile", role: .destructive) { if let renaming { profiles.remove(renaming.id) }; renaming = nil; revision += 1 }
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onAppear(perform: appeared)
        .onChange(of: shell.stage) { _, stage in if stage == .home { onboarding.presentIfNeeded() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { steamGames.refresh(); if SteamOwnedLibrary.enabled { steam.reconcileSession() } }
        }
        .onChange(of: tab) { _, next in if next == .store { loadStore() } }
        .onChange(of: store) { _, _ in shelves = []; storeResults = nil; storeFocus = (-1, 0); loadStore() }
        .onReceive(LibraryController.shared.commands) { handle($0) }
    }

    /// Home, Library, Store and Settings under the top bar, with the hints, sheets and the cover's growth over them.
    private var homeShell: some View {
        ZStack {
            Rectangle().fill(GlassOS.night.opacity(0.66)).background(.ultraThinMaterial.opacity(0.75))
                .ignoresSafeArea().allowsHitTesting(false)
                .opacity(tab == .home ? 0 : 1)
                .animation(GlassMotion.css(0.25), value: tab)
            if tab == .home {
                ZStack {
                    LinearGradient(stops: [.init(color: .black.opacity(0.62), location: 0), .init(color: .clear, location: 0.62)],
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(stops: [.init(color: .black.opacity(0.6), location: 0), .init(color: .clear, location: 0.45)],
                                   startPoint: .bottom, endPoint: .top)
                }
                .ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 8) {
                topBar.padding(.horizontal, sidePadding)
                page.id(tab).transition(.glassPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, sidePadding)
            }
            .padding(.top, 10)
            .ignoresSafeArea(edges: [.horizontal, .bottom])
            VStack {
                Spacer()
                HStack { Spacer(); GlassHintBar(items: hints) }
            }
            .padding(.trailing, sidePadding).padding(.bottom, 12)
            .ignoresSafeArea(edges: [.horizontal, .bottom])
            .opacity(overlay == .controllerTest || overlay == .quick ? 0 : 1)
            overlayLayer
            if let toast {
                VStack {
                    Spacer()
                    Text(toast).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 16).frame(height: 40).glassSurface(radius: 20)
                }
                .padding(.bottom, 18).ignoresSafeArea(edges: .bottom)
                .transition(.glassRise).id(toastRun)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.updatesFrequently)
            }
            openingLayer
        }
        .transition(.opacity)
    }

    private func appeared() {
        EndedSessionSurface.install(); EndedSessionSurface.hide(reason: "library-appeared")
        if shell.stage == .home { onboarding.presentIfNeeded() }
        steamGames.refresh()
        if SteamOwnedLibrary.enabled { steam.start(); steam.reconcileSession() }
        if EpicLibrary.enabled { epic.start() }
        if GOGLibrary.enabled { gog.start() }
        GlassMemory.applyDefaultsIfNeeded()
        LogStore.shared.log("[glass] home games=\(games.count) pads=\(pads.pads.count) stage=\(shell.stage)")
    }

    private func refreshStores() {
        Task {
            if SteamOwnedLibrary.enabled, steam.signedIn { await steam.refreshLibrary(interactive: false) }
            if epic.signedIn { await epic.refreshLibrary(interactive: false) }
            if gog.signedIn { await gog.refreshLibrary(interactive: false) }
        }
    }

    private func sheetClosed() {
        let wasSignedOut = !signedIn
        revision += 1
        refreshStores()
        if tab == .store, wasSignedOut, signedIn { show(toast: "Signed in to \(store.rawValue)"); loadStore() }
    }

    private func show(toast text: String) {
        toastRun += 1
        let run = toastRun
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if toastRun == run { withAnimation(GlassMotion.css(0.2)) { toast = nil } }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Text("Madeira").font(.system(size: 18, weight: .bold)).tracking(-0.3).frame(width: 90, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                GlassShoulderChip(right: false) { stepTab(-1) }
                tabBar
                GlassShoulderChip(right: true) { stepTab(1) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                iconButton("magnifyingglass", "Search", focused: topFocused(0)) { openSearch() }
                iconButton("arrow.down.to.line", "Downloads", focused: topFocused(1), badge: hasTransfers) { openOverlay(.downloads) }
                Button { openOverlay(.quick) } label: {
                    GlassAvatar(profile: profiles.current).frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(GlassPressStyle(scale: 0.92))
                .overlay { if topFocused(2) { GlassFocusRing(radius: 22) } }
                .accessibilityLabel("Quick menu, \(profiles.current.name)")
                GlassClock().frame(minWidth: 44, alignment: .trailing)
            }
        }
        .frame(height: 44)
    }

    private func topFocused(_ index: Int) -> Bool { tab == .home && homeZone == 0 && topButton == index && overlay == nil }

    /// The tab bar: one white pill that slides on the prototype's spring (0.46 s) under four 84-point tabs.
    private var tabBar: some View {
        let index = CGFloat(GlassTab.allCases.firstIndex(of: tab) ?? 0)
        return ZStack(alignment: .topLeading) {
            Capsule().fill(.white).frame(width: 84, height: 36)
                .offset(x: index * 84, y: 3)
                .animation(GlassMotion.spring(0.46), value: tab)
            HStack(spacing: 0) {
                ForEach(GlassTab.allCases) { item in
                    Button { switchTab(item) } label: {
                        Text(item.rawValue).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item == tab ? GlassOS.ink : .white.opacity(0.82))
                            .frame(width: 84, height: 42).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item == tab ? .isSelected : [])
                }
            }
            .animation(GlassMotion.css(0.2), value: tab)
        }
        .padding(.horizontal, 3)
        .frame(height: 44, alignment: .top)
        .glassSurface(radius: 22)
    }

    private func iconButton(_ symbol: String, _ label: String, focused: Bool, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) { if badge { Circle().fill(GlassOS.accent).frame(width: 9, height: 9).padding(9) } }
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.92))
        .glassSurface(radius: 22, interactive: true)
        .overlay { if focused { GlassFocusRing(radius: 22) } }
        .accessibilityLabel(label)
    }

    private var hasTransfers: Bool {
        !steam.downloads.isEmpty || !epic.downloads.isEmpty || !gog.downloads.isEmpty
            || importer.jobs.contains { job in
                if case .done = job.state { return false }
                if case .failed = job.state { return false }
                return true
            }
    }

    private func switchTab(_ next: GlassTab) {
        guard next != tab else { return }
        withAnimation(GlassMotion.ease(0.36)) { tab = next }
    }

    private func stepTab(_ delta: Int) {
        let all = GlassTab.allCases
        let index = all.firstIndex(of: tab) ?? 0
        overlay = nil
        switchTab(all[(index + delta + all.count) % all.count])
    }

    private func openOverlay(_ next: GlassOverlay) {
        overlayFocus = 0
        withAnimation { overlay = next }
    }

    private func openSearch() {
        searchText = ""; searchFocus = 0
        openOverlay(.search)
    }

    private var hints: [(GlassPadButton, String)] {
        if overlay != nil { return [(.accept, "Select"), (.back, "Close")] }
        switch tab {
        case .home:
            guard let game = selected else { return [(.accept, "Import"), (.menu, "Quick menu")] }
            return [(.accept, primaryLabel(game)), (.add, "Details"), (.menu, "Quick menu")]
        case .library: return [(.accept, "Open"), (.back, "Home"), (.menu, "Quick menu")]
        case .store, .settings: return [(.accept, "Select"), (.back, "Home"), (.menu, "Quick menu")]
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .home: home
        case .library: library
        case .store: storePage
        case .settings: settings
        }
    }

    // MARK: Home

    private var home: some View {
        let list = homeGames
        return Group {
            if list.isEmpty {
                VStack(spacing: 10) {
                    Text("No games yet").font(.system(size: 20, weight: .bold))
                    Text("Import a game, or sign in to a store.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 8) {
                        Button("Import") { openOverlay(.importer) }.buttonStyle(GlassButtonStyle(primary: true))
                        Button("Store") { switchTab(.store) }.buttonStyle(GlassButtonStyle())
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 44)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollViewReader { reader in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .center, spacing: 14) {
                                ForEach(list) { game in cover(game) }
                                Button { switchTab(.library) } label: {
                                    Text("All\ngames").font(.system(size: 13, weight: .semibold)).lineSpacing(2).multilineTextAlignment(.center)
                                        .frame(width: 76, height: 114).contentShape(Rectangle())
                                }
                                .buttonStyle(GlassPressStyle())
                                .glassSurface(radius: 12, interactive: true)
                            }
                            .frame(height: 180)
                        }
                        .scrollClipDisabled()
                        .frame(height: 180)
                        .onChange(of: selectedID) { _, id in withAnimation(GlassMotion.spring(0.5)) { reader.scrollTo(id, anchor: .center) } }
                    }
                    if let game = selected { homeInfo(game).padding(.top, 6) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// A cover: 76 × 114, or 120 × 180 with the white ring, the glow and the shine when it is the selected one.
    /// Both the cover that grows and the one that shrinks ride the same spring, so the row never jitters.
    private func cover(_ game: GlassGame) -> some View {
        let on = game.id == selected?.id
        return Button {
            if on { open(game) } else { select(game) }
        } label: {
            GlassCover(game: game)
                .opacity(on ? 1 : 0.8)
                .frame(width: on ? 120 : 76, height: on ? 180 : 114)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(on ? 0.45 : 0), radius: 15, y: 14)
                .overlay { if on { GlassShine().transition(.opacity.animation(GlassMotion.css(0.12))) } }
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white, lineWidth: 2).padding(-4)
                        .opacity(on ? 1 : 0).animation(GlassMotion.css(0.18), value: on)
                }
                .shadow(color: .white.opacity(on ? 0.14 : 0), radius: 18)
                .overlay(alignment: .bottom) {
                    if let progress = game.progress { GlassTrack(value: progress).padding(8) }
                }
                .overlay(alignment: .bottomLeading) {
                    if game.transfer == nil && !game.installed {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 4).padding(6)
                    }
                }
                .background {
                    if on {
                        GeometryReader { geo in
                            Color.clear.onChange(of: geo.frame(in: .global), initial: true) { _, frame in selectedFrame = frame }
                        }
                    }
                }
        }
        .buttonStyle(.plain).id(game.id).accessibilityLabel(game.title)
        .accessibilityValue(game.status)
    }

    private func select(_ game: GlassGame) {
        withAnimation(GlassMotion.spring(0.5)) { selectedID = game.id }
    }

    private func homeInfo(_ game: GlassGame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.title).font(.system(size: 27, weight: .bold)).tracking(-0.3).lineLimit(1).frame(height: 33)
                    Text(game.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.88)).frame(height: 16)
                }
                .id(game.id).transition(.glassInfo)
            }
            .frame(height: 50, alignment: .topLeading)
            HStack(spacing: 8) {
                Button(primaryLabel(game)) { open(game) }
                    .buttonStyle(GlassButtonStyle(compact: true, primary: true))
                    .overlay { if homeZone == 2 && homeButton == 0 { GlassFocusRing(radius: 22) } }
                Button("Details") { showDetails(game) }
                    .buttonStyle(GlassButtonStyle(compact: true))
                    .overlay { if homeZone == 2 && homeButton == 1 { GlassFocusRing(radius: 22) } }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private func showDetails(_ game: GlassGame) {
        selectedID = game.id
        openOverlay(.details(game.id))
    }

    private func primaryLabel(_ game: GlassGame) -> String {
        if game.installed { return "Play" }
        return game.transfer ?? "Install"
    }

    /// Play, or start the download. On the home page the selected cover first grows to fill the
    /// screen (0.56 s, the prototype's `open`), the game's art fading in over it after 0.14 s.
    private func open(_ game: GlassGame) {
        guard let entry = game.entry else { install(game); return }
        guard !GlassMotion.reduced, selectedFrame != .zero, tab == .home, overlay == nil else { play(entry); return }
        opening = (game, selectedFrame)
        openingGrown = false
        openingHero = false
        DispatchQueue.main.async {
            withAnimation(GlassMotion.open(0.56)) { openingGrown = true }
            withAnimation(GlassMotion.css(0.3).delay(0.14)) { openingHero = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            play(entry)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { opening = nil; openingGrown = false; openingHero = false }
        }
    }

    private func install(_ game: GlassGame) {
        if game.transfer != nil { openOverlay(.downloads); return }
        switch game.source {
        case .steam: if let id = game.steamID { steam.install(id) }
        case .epic: if let key = game.storeKey { epic.install(key) }
        case .gog: if let key = game.storeKey { gog.install(key) }
        case .imported: return
        }
        show(toast: "Downloading \(game.title)")
    }

    @ViewBuilder private var openingLayer: some View {
        if let opening {
            GeometryReader { geo in
                let full = geo.frame(in: .global)
                let start = opening.frame
                ZStack {
                    GlassCover(game: opening.game)
                    GlassBackdrop(game: opening.game).opacity(openingHero ? 1 : 0)
                }
                .frame(width: openingGrown ? full.width : start.width, height: openingGrown ? full.height : start.height)
                .clipShape(RoundedRectangle(cornerRadius: openingGrown ? 0 : 12, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 22, y: 18)
                .position(x: (openingGrown ? full.midX : start.midX) - full.minX, y: (openingGrown ? full.midY : start.midY) - full.minY)
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
        }
    }

    // MARK: Library

    private var library: some View {
        let list = libraryGames
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                GlassSegment(options: Self.filters, selected: libraryFilter, glass: true, focused: libraryZone == 0) { index in
                    libraryFilter = index; libraryFocus = 0
                }
                Spacer()
                Button("Import") { openOverlay(.importer) }.buttonStyle(GlassButtonStyle())
            }
            if list.isEmpty {
                Text("Nothing here yet").font(.system(size: 15)).foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 44)
            } else {
                ScrollViewReader { reader in
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(114), spacing: 14), count: 6), alignment: .leading, spacing: 16) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, game in
                                Button { showDetails(game) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        GlassCover(game: game).frame(width: 114, height: 168)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay { if libraryZone == 1 && index == libraryFocus { GlassFocusRing(radius: 14) } }
                                            .overlay(alignment: .bottom) { if let progress = game.progress { GlassTrack(value: progress).padding(8) } }
                                        Text(game.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        Text(game.transfer ?? game.source.rawValue).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
                                            .lineLimit(1).padding(.top, -5)
                                    }
                                    .frame(width: 114, alignment: .leading)
                                }
                                .buttonStyle(GlassPressStyle(scale: 0.97)).id(index)
                                .accessibilityLabel(game.title).accessibilityValue(game.status)
                            }
                        }
                        .padding(4).padding(.bottom, 44)
                    }
                    .padding(-4)
                    .onChange(of: libraryFocus) { _, index in withAnimation(GlassMotion.ease(0.36)) { reader.scrollTo(index, anchor: .center) } }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Store

    private var signedIn: Bool {
        switch store {
        case .steam: return SteamSignIn.isSignedIn
        case .epic: return epic.signedIn
        case .gog: return gog.signedIn
        }
    }

    private var storeAccount: String {
        guard signedIn else { return "Not signed in" }
        let name: String?
        switch store {
        case .steam: name = SteamSignIn.accountName
        case .epic: name = epic.accountName
        case .gog: name = gog.accountName
        }
        return name.map { "Signed in as \($0)" } ?? "Signed in"
    }

    private func loadStore() {
        guard tab == .store, signedIn, shelves.isEmpty, !storeLoading else { return }
        storeLoading = true
        let kind = store
        Task {
            let result: [GlassStoreShelf]
            switch kind {
            case .steam: result = (try? await GlassStoreAPI.steamShelves()) ?? []
            case .epic: result = (try? await GlassStoreAPI.epicShelves()) ?? []
            case .gog: result = (try? await GlassStoreAPI.gogShelves()) ?? []
            }
            if kind == store { shelves = result }
            storeLoading = false
        }
    }

    private var visibleShelves: [GlassStoreShelf] {
        if let storeResults { return [GlassStoreShelf(title: "Results for “\(storeQuery)”", items: storeResults)] }
        return shelves
    }

    private var storePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GlassSegment(options: GlassStoreKind.allCases.map(\.rawValue), selected: GlassStoreKind.allCases.firstIndex(of: store) ?? 0,
                             glass: true, focused: storeFocus.shelf == -1 && overlay == nil) { index in
                    store = GlassStoreKind.allCases[index]
                }
                if signedIn {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        TextField("Search \(store.rawValue)", text: $storeQuery).font(.system(size: 14))
                            .submitLabel(.search).onSubmit(runStoreSearch)
                    }
                    .padding(.horizontal, 14).frame(height: 44).frame(maxWidth: 220)
                    .glassSurface(radius: 22)
                }
                Spacer(minLength: 8)
                Text(storeAccount).font(.system(size: 13)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
            }
            storePanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassSurface(radius: 24)
                .padding(.bottom, 44)
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var storePanel: some View {
        if !signedIn {
            VStack(spacing: 10) {
                Text("Sign in to \(store.rawValue)").font(.system(size: 20, weight: .bold))
                Text("Your games and purchases appear here, and Madeira downloads them.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                Button("Sign in") { sheet = .signIn(store) }.buttonStyle(GlassButtonStyle(primary: true))
                    .overlay { if storeFocus.shelf == 0 { GlassFocusRing(radius: 22) } }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if storeLoading && visibleShelves.isEmpty {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleShelves.isEmpty {
            VStack(spacing: 10) {
                Text(store == .epic ? "Epic's full catalogue is on its site" : "The store didn't answer").font(.system(size: 16, weight: .semibold))
                Button("Open \(store.rawValue)") { sheet = .web(store.rawValue, store.home) }.buttonStyle(GlassButtonStyle(primary: true))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleShelves.enumerated()), id: \.element.id) { row, shelf in
                            Text(shelf.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                                .padding(.top, row == 0 ? 10 : 18).padding(.bottom, 2)
                            ForEach(Array(shelf.items.enumerated()), id: \.element.id) { column, item in
                                storeRow(item, focused: storeFocus.shelf == row && storeFocus.item == column, last: column == shelf.items.count - 1)
                                    .id("\(row)-\(column)")
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
                .onChange(of: storeFocus.shelf) { _, _ in scrollStore(reader) }
                .onChange(of: storeFocus.item) { _, _ in scrollStore(reader) }
            }
        }
    }

    /// A store row as the prototype draws it: the cover, title and details, then Buy, Install, Open or the download.
    private func storeRow(_ item: GlassStoreItem, focused: Bool, last: Bool) -> some View {
        let game = owned(item)
        return HStack(spacing: 14) {
            Button { openStoreItem(item) } label: {
                HStack(spacing: 14) {
                    AsyncImage(url: item.image) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                        .frame(width: 42, height: 62).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        Text(game == nil ? "\(item.store.rawValue) · \(item.price)" : "In your library · " + (game?.status ?? ""))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let game, let progress = game.progress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.transfer ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                    GlassTrack(value: progress)
                }.frame(width: 150)
            } else if let game, game.installed {
                Button("Open") { showDetails(game) }.buttonStyle(GlassButtonStyle(tinted: true))
            } else if let game {
                Button("Install") { install(game) }.buttonStyle(GlassButtonStyle(primary: true))
            } else {
                Button(item.price == "Free" ? "Get" : "Buy · \(item.price)") { openStoreItem(item) }
                    .buttonStyle(GlassButtonStyle(primary: true)).frame(minWidth: 92)
            }
        }
        .frame(minHeight: 76)
        .background {
            if focused { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.1)).padding(.horizontal, -8) }
        }
        .overlay {
            if focused { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 1.5).padding(.horizontal, -8) }
        }
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) } }
    }

    private func scrollStore(_ reader: ScrollViewProxy) {
        withAnimation(GlassMotion.ease(0.36)) { reader.scrollTo("\(storeFocus.shelf)-\(storeFocus.item)", anchor: .center) }
    }

    private func runStoreSearch() {
        let text = storeQuery.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { storeResults = nil; return }
        if store == .epic { sheet = .web("Epic", store.search(text)); return }
        let kind = store
        Task {
            let found = kind == .steam ? try? await GlassStoreAPI.steamSearch(text) : try? await GlassStoreAPI.gog(query: text, order: "desc:score")
            storeResults = found ?? []
            storeFocus = (0, 0)
        }
    }

    private func openStoreItem(_ item: GlassStoreItem) {
        storeItem = item; storeDetails = nil
        openOverlay(.storeItem(item.id))
        Task {
            let details = await GlassStoreAPI.details(item)
            if storeItem?.id == item.id { storeDetails = details }
        }
    }

    private func owned(_ item: GlassStoreItem) -> GlassGame? {
        switch item.store {
        case .steam: return games.first { $0.steamID == Int(item.key) }
        case .gog: return games.first { $0.source == .gog && $0.storeKey == item.key }
        case .epic: return games.first { $0.source == .epic && $0.title.caseInsensitiveCompare(item.name) == .orderedSame }
        }
    }

    // MARK: Settings

    private let categories = ["Account", "Controllers", "Performance", "Appearance", "JIT & System", "Storage", "About"]

    private func openTest() { openOverlay(.controllerTest) }

    private var settingsRows: [GlassRow] {
        _ = revision
        switch settingsCategory {
        case 0:
            var rows = [
                GlassRow(title: "Steam", kind: .action(SteamSignIn.accountName ?? "Sign in") { sheet = .signIn(.steam) }),
                GlassRow(title: "Epic Games", kind: .action(epic.accountName ?? (epic.signedIn ? "Signed in" : "Sign in")) { sheet = .signIn(.epic) }),
                GlassRow(title: "GOG", kind: .action(gog.accountName ?? (gog.signedIn ? "Signed in" : "Sign in")) { sheet = .signIn(.gog) })
            ]
            for profile in profiles.list {
                rows.append(GlassRow(title: "Profile · \(profile.name)", detail: profile.id == profiles.currentID ? "Playing now" : nil,
                                     kind: .action("Rename") { renameText = profile.name; renaming = profile }))
            }
            rows.append(GlassRow(title: "Add a profile", detail: "Profiles are names on this device for \"Who's playing?\". Store sign-ins are shared.",
                                 kind: .action(nil) { profiles.add(); revision += 1 }))
            return rows
        case 1:
            var rows: [GlassRow] = pads.pads.map { pad in
                let battery = pad.battery.map { " · \(Int($0.batteryLevel * 100))%" } ?? ""
                return GlassRow(title: pad.vendorName ?? pad.productCategory, kind: .info(padName(pad) + battery))
            }
            if rows.isEmpty {
                rows.append(GlassRow(title: "No controller connected",
                                     detail: "Put it in pairing mode, then pair it in iOS Settings › Bluetooth. A DualSense pairs by holding Create and PS.",
                                     kind: .info("")))
            }
            rows.append(GlassRow(title: pads.searching ? "Looking for controllers…" : "Find my controller", kind: .action(nil) { pads.search() }))
            rows.append(GlassRow(title: "Test controller", detail: "Buttons, sticks, rumble and adaptive triggers.", kind: .action(nil) { openTest() }))
            let dualSense = ["hid", "dualsense"].contains(MadeiraConfig.get(GamepadInput.padModeKey)?.lowercased() ?? "")
            rows.append(GlassRow(title: "Games see my pad as", detail: dualSense
                                 ? "DualSense: adaptive triggers and light bar in games that support it. Games that only know Xbox pads won't see it."
                                 : "Xbox: works in every game, with rumble.",
                                 kind: .choice(["Xbox", "DualSense"], dualSense ? 1 : 0) { index in
                _ = MadeiraConfig.set(GamepadInput.padModeKey, index == 1 ? "hid" : nil)
                revision += 1
            }))
            let output = MadeiraConfig.get("env.MADEIRA_PAD_OUTPUT") ?? "1"
            rows.append(GlassRow(title: "Rumble and triggers in games", kind: .toggle(output != "0") { on in
                _ = MadeiraConfig.set("env.MADEIRA_PAD_OUTPUT", on ? nil : "0")
                revision += 1
            }))
            return rows
        case 2:
            let current = GlassMemory.choice
            return [
                GlassRow(title: "Memory saver",
                         detail: "Keeps game memory outside Madeira's iOS limit, which lets bigger games run. Applies at the next game start.",
                         kind: .choice(GlassMemory.labels, GlassMemory.values.firstIndex(of: current) ?? 0) { index in
                    GlassMemory.choice = GlassMemory.values[index]
                    revision += 1
                }),
                GlassRow(title: "Back off under memory pressure",
                         detail: "Stops taking saved memory when iOS runs low, so the phone doesn't freeze.",
                         kind: .toggle(MadeiraConfig.get("donor-pool-guard") != "0") { on in
                    _ = MadeiraConfig.set("donor-pool-guard", on ? "1" : "0")
                    revision += 1
                }),
                GlassRow(title: "Device memory", kind: .info(String(format: "%.0f GB", GlassMemory.deviceGB)))
            ]
        case 3:
            return [
                GlassRow(title: "Surfaces", detail: "Current glass is the look from the first Glass builds.",
                         kind: .choice(GlassStyle.allCases.map(\.rawValue), GlassStyle.allCases.firstIndex(of: GlassStyle.chosen) ?? 0) { index in
                    UserDefaults.standard.set(GlassStyle.allCases[index].rawValue, forKey: GlassStyle.key)
                    revision += 1
                }),
                GlassRow(title: "Startup animation", detail: "The Madeira emblem when the app opens.", kind: .toggle(GlassOS.bootAnimation) { on in
                    UserDefaults.standard.set(on, forKey: GlassOS.bootKey)
                    revision += 1
                }),
                GlassRow(title: "Ask who's playing", detail: "The profile picker after the startup animation.", kind: .toggle(GlassOS.askProfile) { on in
                    UserDefaults.standard.set(on, forKey: GlassOS.askProfileKey)
                    revision += 1
                }),
                GlassRow(title: "Glass interface", detail: "Off returns to the classic library at the next start.", kind: .toggle(GlassUI.enabled) { on in
                    UserDefaults.standard.set(on, forKey: GlassUI.key)
                    revision += 1
                })
            ]
        case 4:
            return [
                GlassRow(title: "JIT", detail: "Games need JIT to run.", kind: jitState.enabled ? .info("Enabled") : .action("Enable") { enableJIT() }),
                GlassRow(title: "Device memory", kind: .info(String(format: "%.0f GB", GlassMemory.deviceGB))),
                GlassRow(title: "All settings", detail: "Madeira's full settings, including graphics and diagnostics.", kind: .action(nil) { sheet = .classicSettings })
            ]
        case 5:
            let formatter = ByteCountFormatter()
            let installed = model.entries.compactMap(\.folderBytes).reduce(0, +)
            return [GlassRow(title: "Installed games", kind: .info(formatter.string(fromByteCount: installed))),
                    GlassRow(title: "Free storage", kind: .info(formatter.string(fromByteCount: GlassImporter.freeBytes())))]
        default:
            return [GlassRow(title: "Madeira", kind: .info(GlassOS.version)),
                    GlassRow(title: "What it does", kind: .info("Windows games on iOS")),
                    GlassRow(title: "Interface", kind: .info("Madeira Glass"))]
        }
    }

    private func padName(_ pad: GCController) -> String {
        switch GlassPadFamily.of(pad) {
        case .playStation: return "PlayStation"
        case .xbox: return "Xbox"
        case .generic: return "Controller"
        }
    }

    /// The prototype's settings: a 186-point list of categories, and the chosen one's rows beside it.
    private var settings: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(categories.indices, id: \.self) { index in
                        let on = index == settingsCategory
                        Button { settingsCategory = index; settingsFocus = -1 } label: {
                            Text(categories[index]).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(on ? GlassOS.ink : .white.opacity(0.86))
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                .background { if on { RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white) } }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .animation(GlassMotion.css(0.18), value: settingsCategory)
                .padding(5)
            }
            .frame(width: 186).frame(maxHeight: .infinity, alignment: .top)
            .glassSurface(radius: 22)
            .overlay { if settingsFocus < 0 && overlay == nil { GlassFocusRing(radius: 22) } }
            let rows = settingsRows
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(categories[settingsCategory]).font(.system(size: 19, weight: .bold)).frame(height: 24).padding(.bottom, 2)
                        GlassRowList(rows: rows, focus: settingsFocus)
                    }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 6)
                    .id(settingsCategory).transition(.glassPage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .glassSurface(radius: 22)
                .onChange(of: settingsFocus) { _, index in withAnimation(GlassMotion.ease(0.36)) { reader.scrollTo(index, anchor: .center) } }
            }
        }
        .padding(.bottom, 44)
    }

    // MARK: Overlays

    @ViewBuilder private var overlayLayer: some View {
        if let overlay {
            Button { close() } label: { Color.black.opacity(0.38).ignoresSafeArea() }
                .buttonStyle(.plain).accessibilityLabel("Close")
                .transition(.opacity.animation(GlassMotion.css(0.2)))
            Group {
                switch overlay {
                case .details(let id):
                    if let game = games.first(where: { $0.id == id }) { detailsCard(game).transition(.glassRise) }
                case .search:
                    VStack { searchCard; Spacer(minLength: 0) }.padding(.top, 14).transition(.glassRise)
                case .downloads:
                    VStack { HStack { Spacer(); downloadsCard }; Spacer(minLength: 0) }
                        .padding(.top, 62).padding(.trailing, sidePadding)
                        .transition(.glassRise(anchor: .topTrailing))
                case .importer: importCard.transition(.glassRise)
                case .storeItem: if let storeItem { storeItemCard(storeItem).transition(.glassRise) }
                case .controllerTest:
                    GlassControllerTest(close: { self.overlay = nil }).padding(.horizontal, 40).padding(.vertical, 10).transition(.glassRise)
                case .quick:
                    VStack { Spacer(minLength: 0); quickCard }
                        .padding(.horizontal, sidePadding).padding(.bottom, 12)
                        .transition(.glassRise(anchor: .bottom))
                }
            }
            .ignoresSafeArea(edges: [.horizontal, .bottom])
        }
    }

    private func close() { withAnimation { overlay = nil } }

    private func detailsActions(_ game: GlassGame) -> [(String, () -> Void)] {
        var list: [(String, () -> Void)] = [(primaryLabel(game), { close(); open(game) })]
        if let entry = game.entry { list.append(("Game settings", { sheet = .gameSettings(entry) })) }
        return list
    }

    /// The prototype's details sheet: 580 × 310, the cover, the title, Source, Size and Status, and Play across the bottom.
    private func detailsCard(_ game: GlassGame) -> some View {
        let actions = detailsActions(game)
        let size = game.entry?.folderBytes.map { ByteCountFormatter().string(fromByteCount: $0) } ?? "—"
        let facts = [("Source", game.source.rawValue), ("Size", size), ("Status", game.installed ? "Installed" : game.transfer ?? "Not installed")]
        return HStack(alignment: .top, spacing: 20) {
            GlassCover(game: game).frame(width: 180, height: 270).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(game.title).font(.system(size: 24, weight: .bold)).lineLimit(2).padding(.trailing, 44)
                Text(game.subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.82)).padding(.top, 2)
                VStack(spacing: 0) {
                    ForEach(facts.indices, id: \.self) { index in
                        HStack {
                            Text(facts[index].0).foregroundStyle(.white.opacity(0.78))
                            Spacer()
                            Text(facts[index].1).fontWeight(.medium)
                        }
                        .font(.system(size: 14)).padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                    }
                }
                .padding(.top, 12)
                if let progress = game.progress { GlassTrack(value: progress).padding(.top, 10) }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    ForEach(actions.indices, id: \.self) { index in
                        Button(actions[index].0) { actions[index].1() }
                            .buttonStyle(GlassButtonStyle(primary: index == 0, tinted: index > 0, wide: index == 0))
                            .overlay { if index == overlayFocus { GlassFocusRing(radius: 22) } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 580, height: 310)
        .overlay(alignment: .topTrailing) { GlassCloseButton { close() }.padding(10) }
        .glassSurface(radius: 30)
    }

    private var searchResults: [GlassGame] {
        let list = games
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? list : list.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// The prototype's search sheet: 480 × 362, near the top.
    private var searchCard: some View {
        let results = searchResults
        return VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold))
                TextField("Search games", text: $searchText).font(.system(size: 16)).frame(height: 44)
                    .submitLabel(.search)
                GlassCloseButton { close() }
            }
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, game in
                            Button { showDetails(game) } label: {
                                HStack(spacing: 12) {
                                    GlassCover(game: game).frame(width: 32, height: 46).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                        Text(game.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6).frame(minHeight: 56)
                                .background {
                                    if index == searchFocus && !pads.pads.isEmpty {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(GlassPressStyle(scale: 0.98)).id(index)
                        }
                        if results.isEmpty {
                            Text("No games match that name").font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).padding(.vertical, 40)
                        }
                    }
                }
                .onChange(of: searchFocus) { _, index in withAnimation(GlassMotion.ease(0.36)) { reader.scrollTo(index, anchor: .center) } }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(width: 480, height: 362)
        .glassSurface(radius: 30)
    }

    private struct Transfer: Identifiable {
        var id: String
        var title: String
        var fraction: Double
        var status: String
        var stop: () -> Void
        var stopLabel = "Cancel"
    }

    private var transfers: [Transfer] {
        var list: [Transfer] = []
        for game in games where game.transfer != nil {
            list.append(Transfer(id: game.id, title: game.title, fraction: game.progress ?? 0, status: game.transfer ?? "", stop: {
                switch game.source {
                case .steam: if let id = game.steamID { steam.pause(id) }
                case .epic: if let key = game.storeKey { epic.pause(key) }
                case .gog: if let key = game.storeKey { gog.pause(key) }
                case .imported: break
                }
            }, stopLabel: "Pause"))
        }
        for job in importer.jobs {
            let status: String
            var fraction = job.fraction
            switch job.state {
            case .checking: status = job.note.isEmpty ? "Checking" : job.note
            case .needsApproval: status = "Waiting for your answer"
            case .running: status = job.note
            case .finishing: status = job.note
            case .done: status = job.note; fraction = 1
            case .failed(let why): status = why
            }
            let settled: Bool
            switch job.state {
            case .done, .failed: settled = true
            default: settled = false
            }
            list.append(Transfer(id: job.id.uuidString, title: job.name, fraction: fraction, status: status,
                                 stop: { settled ? importer.dismiss(job.id) : importer.cancel(job.id) },
                                 stopLabel: settled ? "Clear" : "Stop"))
        }
        return list
    }

    /// The prototype's downloads sheet: 340 wide, under the Downloads button, growing from its corner.
    private var downloadsCard: some View {
        let list = transfers
        return VStack(alignment: .leading, spacing: 0) {
            Text("Downloads").font(.system(size: 18, weight: .bold)).frame(height: 24).padding(.bottom, 8)
            if list.isEmpty {
                Text("Nothing downloading. Install a game from the Store or import one, and it shows up here.")
                    .font(.system(size: 14)).lineSpacing(3).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2).padding(.bottom, 14)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                        Spacer()
                                        Text("\(Int(min(1, item.fraction) * 100))%").font(.system(size: 14)).monospacedDigit()
                                    }
                                    GlassTrack(value: item.fraction)
                                    Text(item.status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                                }
                                Button(item.stopLabel, action: item.stop).buttonStyle(GlassButtonStyle(compact: true, tinted: true))
                                    .overlay { if index == overlayFocus { GlassFocusRing(radius: 22) } }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(width: 340, alignment: .topLeading)
        .frame(minHeight: 130, alignment: .top)
        .glassSurface(radius: 30)
    }

    private var importChoices: [(String, () -> Void)] {
        var list: [(String, () -> Void)] = [("Choose from Files", { picking = true })]
        for url in GlassImporter.waitingArchives().prefix(3) {
            list.append((url.lastPathComponent, { importer.start(url, scoped: false); openOverlay(.downloads) }))
        }
        return list
    }

    /// The prototype's import sheet: 420 wide.
    private var importCard: some View {
        let choices = importChoices
        return VStack(alignment: .leading, spacing: 0) {
            Text("Import a game").font(.system(size: 20, weight: .bold)).frame(height: 26)
            Text("A folder, a program, or a .zip, .rar or .7z. Madeira copies it into its Windows drive and adds it to your library.")
                .font(.system(size: 13)).lineSpacing(3).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            VStack(spacing: 10) {
                ForEach(choices.indices, id: \.self) { index in
                    Button(choices[index].0) { choices[index].1() }
                        .buttonStyle(GlassButtonStyle(primary: index == 0, tinted: index > 0, wide: true))
                        .overlay { if index == overlayFocus { GlassFocusRing(radius: 22) } }
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(width: 420)
        .glassSurface(radius: 30)
    }

    private func storeActions(_ item: GlassStoreItem) -> [(String, () -> Void)] {
        var list: [(String, () -> Void)] = []
        if let game = owned(item) {
            list.append((game.installed ? "In your library" : primaryLabel(game), {
                if !game.installed { install(game) }
                showDetails(game)
            }))
        } else {
            let label = item.price == "Free" ? "Add to library" : "Buy for \(item.price)"
            // Buying needs the store's own checkout: none of the three lets an app take a payment.
            list.append((label, { let page = item.page; overlay = nil; sheet = .web("Checkout · " + item.store.rawValue, page) }))
        }
        return list
    }

    /// The prototype's buy sheet: 540 × 290, the cover, the title, Price and how it is paid, and the button across the bottom.
    private func storeItemCard(_ item: GlassStoreItem) -> some View {
        let actions = storeActions(item)
        return HStack(alignment: .top, spacing: 20) {
            AsyncImage(url: item.image) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                .frame(width: 166, height: 250).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.system(size: 22, weight: .bold)).lineLimit(2).padding(.trailing, 44)
                Text(item.store.rawValue).font(.system(size: 14)).foregroundStyle(.white.opacity(0.82)).padding(.top, 2)
                VStack(spacing: 0) {
                    fact("Price", item.price)
                    fact("Pay with", "Your \(item.store.rawValue) account")
                }
                .padding(.top, 14)
                if let details = storeDetails, !details.description.isEmpty {
                    ScrollView(showsIndicators: false) {
                        Text(details.description).font(.system(size: 12)).lineSpacing(2).foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                } else {
                    Text("Check how well a game runs before you buy: not every Windows game works in Madeira.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).padding(.top, 8)
                    Spacer(minLength: 0)
                }
                ForEach(actions.indices, id: \.self) { index in
                    Button(actions[index].0) { actions[index].1() }
                        .buttonStyle(GlassButtonStyle(primary: index == 0, wide: true))
                        .overlay { if index == overlayFocus { GlassFocusRing(radius: 22) } }
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 540, height: 290)
        .overlay(alignment: .topTrailing) { GlassCloseButton { close() }.padding(10) }
        .glassSurface(radius: 30)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.78))
            Spacer()
            Text(value).fontWeight(.semibold).lineLimit(1)
        }
        .font(.system(size: 14)).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }

    // MARK: Quick menu

    private var quickTiles: [(label: String, value: String, run: () -> Void)] {
        let transfersCount = transfers.filter { $0.fraction < 1 }.count
        let pad = pads.active
        let padValue = pad.map { p in padName(p) + (p.battery.map { " · \(Int($0.batteryLevel * 100))%" } ?? "") } ?? "Not connected"
        let memory = GlassMemory.labels[GlassMemory.values.firstIndex(of: GlassMemory.choice) ?? 0]
        return [
            ("User", "Switch user", { overlay = nil; shell.switchUser() }),
            ("Downloads", transfersCount > 0 ? "\(transfersCount) active" : "None", { openOverlay(.downloads) }),
            ("Controller", padValue, { overlay = nil; settingsCategory = 1; settingsFocus = -1; switchTab(.settings) }),
            ("Memory saver", memory, {
                let values = GlassMemory.values
                let next = values[((values.firstIndex(of: GlassMemory.choice) ?? 0) + 1) % values.count]
                GlassMemory.choice = next
                revision += 1
                show(toast: "Memory saver: " + GlassMemory.labels[values.firstIndex(of: next) ?? 0] + ", from the next game")
            }),
            ("Power", "Restart Madeira", { overlay = nil; tab = .home; shell.restart() })
        ]
    }

    /// The prototype's quick menu: a bar along the bottom with who is playing, the time, and five tiles.
    private var quickCard: some View {
        _ = revision
        let tiles = quickTiles
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    GlassAvatar(profile: profiles.current, size: 22, ring: false)
                    Text(profiles.current.name).font(.system(size: 15, weight: .bold))
                }
                Spacer()
                HStack(spacing: 0) {
                    GlassDateLine()
                    Text(" · ")
                    GlassClock(size: 13, weight: .regular)
                }
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.82))
            }
            .frame(height: 24)
            HStack(spacing: 10) {
                ForEach(tiles.indices, id: \.self) { index in
                    GlassQuickTile(label: tiles[index].label, value: tiles[index].value,
                                   focused: index == overlayFocus && !pads.pads.isEmpty, action: tiles[index].run)
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity).frame(height: 128)
        .glassSurface(radius: 30)
    }

    @ViewBuilder private func sheetView(_ sheet: GlassSheet) -> some View {
        let back = { self.sheet = nil }
        switch sheet {
        case .signIn(.steam): SteamSignInView().glassPointer(back: back)
        case .signIn(.epic): EpicSignInView().glassPointer(back: back)
        case .signIn(.gog): GOGSignInView().glassPointer(back: back)
        case .web(let title, let url): GlassWebStore(title: title, url: url, closed: {})
        case .gameSettings(let entry):
            NavigationStack { LibraryDetail(entry: entry, play: { game in self.sheet = nil; play(game) }) }.glassPointer(back: back)
        case .classicSettings:
            NavigationStack { LibraryView(play: play, enableJIT: enableJIT, startDock: startDock, initialTab: 1) }.glassPointer(back: back)
        case .jit: JITSetupView().glassPointer(back: back)
        case .files: EmptyView()
        }
    }

    // MARK: Controller

    private func handle(_ command: String) {
        guard shell.stage == .home, sheet == nil, !picking, !onboarding.presented, opening == nil else { return }
        // A system alert has no focus to move, so the pad answers it directly.
        if importer.approval != nil {
            if command == "accept" { importer.answer(approve: true) } else if command == "back" { importer.answer(approve: false) }
            return
        }
        if model.error != nil {
            if command == "accept" || command == "back" { model.error = nil }
            return
        }
        if overlay == .controllerTest { return }
        if let overlay { handleOverlay(overlay, command); return }
        switch command {
        case "tabLeft": stepTab(-1); return
        case "tabRight": stepTab(1); return
        case "menu": openOverlay(.quick); return
        case "action":
            if tab == .store, signedIn { sheet = .web(store.rawValue, store.home) } else { openSearch() }
            return
        default: break
        }
        switch tab {
        case .home: handleHome(command)
        case .library: handleLibrary(command)
        case .store: handleStore(command)
        case .settings: handleSettings(command)
        }
    }

    private func handleHome(_ command: String) {
        let list = homeGames
        guard !list.isEmpty else {
            if command == "accept" { openOverlay(.importer) }
            return
        }
        let index = list.firstIndex { $0.id == selected?.id } ?? 0
        switch (homeZone, command) {
        case (0, "left"): topButton = max(0, topButton - 1)
        case (0, "right"): topButton = min(2, topButton + 1)
        case (0, "down"), (0, "back"): homeZone = 1
        case (0, "accept"):
            switch topButton {
            case 0: openSearch()
            case 1: openOverlay(.downloads)
            default: openOverlay(.quick)
            }
        case (1, "left"): if index > 0 { select(list[index - 1]) }
        case (1, "right"):
            if index + 1 < list.count { select(list[index + 1]) } else { switchTab(.library) }
        case (1, "up"): homeZone = 0
        case (1, "down"): homeZone = 2; homeButton = 0
        case (1, "accept"): if let game = selected { open(game) }
        case (_, "add"): if let game = selected { showDetails(game) }
        case (2, "left"): homeButton = 0
        case (2, "right"): homeButton = 1
        case (2, "up"), (2, "back"): homeZone = 1
        case (2, "accept"):
            guard let game = selected else { return }
            if homeButton == 0 { open(game) } else { showDetails(game) }
        default: break
        }
    }

    private func handleLibrary(_ command: String) {
        let list = libraryGames
        if libraryZone == 0 {
            switch command {
            case "left": libraryFilter = max(0, libraryFilter - 1); libraryFocus = 0
            case "right": libraryFilter = min(Self.filters.count - 1, libraryFilter + 1); libraryFocus = 0
            case "down", "accept": libraryZone = 1
            case "add": openOverlay(.importer)
            case "back": switchTab(.home)
            default: break
            }
            return
        }
        switch command {
        case "left": libraryFocus = max(0, libraryFocus - 1)
        case "right": libraryFocus = min(max(0, list.count - 1), libraryFocus + 1)
        case "up": if libraryFocus >= 6 { libraryFocus -= 6 } else { libraryZone = 0 }
        case "down": libraryFocus = min(max(0, list.count - 1), libraryFocus + 6)
        case "accept": if list.indices.contains(libraryFocus) { showDetails(list[libraryFocus]) }
        case "add": openOverlay(.importer)
        case "back": switchTab(.home)
        default: break
        }
    }

    private func handleStore(_ command: String) {
        let kinds = GlassStoreKind.allCases
        let rows = visibleShelves
        if storeFocus.shelf < 0 {
            let index = kinds.firstIndex(of: store) ?? 0
            switch command {
            case "left": store = kinds[max(0, index - 1)]
            case "right": store = kinds[min(kinds.count - 1, index + 1)]
            case "down": if !signedIn { storeFocus = (0, 0) } else if !rows.isEmpty { storeFocus = (0, 0) }
            case "accept": if !signedIn { sheet = .signIn(store) } else if rows.isEmpty { sheet = .web(store.rawValue, store.home) }
            case "back": switchTab(.home)
            default: break
            }
            return
        }
        if !signedIn {
            switch command {
            case "accept": sheet = .signIn(store)
            case "up", "back": storeFocus = (-1, 0)
            default: break
            }
            return
        }
        guard rows.indices.contains(storeFocus.shelf) else { storeFocus = (-1, 0); return }
        let row = rows[storeFocus.shelf]
        switch command {
        case "down":
            if storeFocus.item + 1 < row.items.count { storeFocus.item += 1 }
            else if storeFocus.shelf + 1 < rows.count { storeFocus = (storeFocus.shelf + 1, 0) }
        case "up":
            if storeFocus.item > 0 { storeFocus.item -= 1 }
            else if storeFocus.shelf > 0 { storeFocus = (storeFocus.shelf - 1, max(0, rows[storeFocus.shelf - 1].items.count - 1)) }
            else { storeFocus = (-1, 0) }
        case "accept":
            if row.items.indices.contains(storeFocus.item) { openStoreItem(row.items[storeFocus.item]) }
        case "back": storeFocus = (-1, 0)
        default: break
        }
    }

    private func handleSettings(_ command: String) {
        let rows = settingsRows
        if settingsFocus < 0 {
            switch command {
            case "up": settingsCategory = max(0, settingsCategory - 1)
            case "down": settingsCategory = min(categories.count - 1, settingsCategory + 1)
            case "right", "accept": if !rows.isEmpty { settingsFocus = 0 }
            case "back": switchTab(.home)
            default: break
            }
            return
        }
        switch command {
        case "up": settingsFocus = max(0, settingsFocus - 1)
        case "down": settingsFocus = min(rows.count - 1, settingsFocus + 1)
        case "left":
            if rows.indices.contains(settingsFocus), rows[settingsFocus].steps,
               case .choice(_, let selected, _) = rows[settingsFocus].kind, selected == 0 { settingsFocus = -1 }
            else if rows.indices.contains(settingsFocus), rows[settingsFocus].steps { rows[settingsFocus].step(-1) }
            else { settingsFocus = -1 }
        case "right": if rows.indices.contains(settingsFocus) { rows[settingsFocus].step(1) }
        case "accept": if rows.indices.contains(settingsFocus) { rows[settingsFocus].accept() }
        case "back": settingsFocus = -1
        default: break
        }
    }

    private func handleOverlay(_ overlay: GlassOverlay, _ command: String) {
        if command == "back" || (command == "menu" && overlay == .quick) { close(); return }
        func move(_ count: Int, _ delta: Int) { overlayFocus = min(max(0, overlayFocus + delta), max(0, count - 1)) }
        switch overlay {
        case .details(let id):
            guard let game = games.first(where: { $0.id == id }) else { return }
            let actions = detailsActions(game)
            switch command {
            case "left": move(actions.count, -1)
            case "right": move(actions.count, 1)
            case "accept": if actions.indices.contains(overlayFocus) { actions[overlayFocus].1() }
            default: break
            }
        case .storeItem:
            guard let storeItem else { return }
            let actions = storeActions(storeItem)
            switch command {
            case "up": move(actions.count, -1)
            case "down": move(actions.count, 1)
            case "accept": if actions.indices.contains(overlayFocus) { actions[overlayFocus].1() }
            default: break
            }
        case .search:
            let results = searchResults
            switch command {
            case "up": searchFocus = max(0, searchFocus - 1)
            case "down": searchFocus = min(max(0, results.count - 1), searchFocus + 1)
            case "accept": if results.indices.contains(searchFocus) { showDetails(results[searchFocus]) }
            default: break
            }
        case .downloads:
            let list = transfers
            switch command {
            case "up": move(list.count, -1)
            case "down": move(list.count, 1)
            case "accept": if list.indices.contains(overlayFocus) { list[overlayFocus].stop() }
            default: break
            }
        case .importer:
            let choices = importChoices
            switch command {
            case "up": move(choices.count, -1)
            case "down": move(choices.count, 1)
            case "accept": if choices.indices.contains(overlayFocus) { choices[overlayFocus].1() }
            default: break
            }
        case .quick:
            let tiles = quickTiles
            switch command {
            case "left": move(tiles.count, -1)
            case "right": move(tiles.count, 1)
            case "accept": if tiles.indices.contains(overlayFocus) { tiles[overlayFocus].run() }
            default: break
            }
        case .controllerTest: break
        }
    }
}

// MARK: - Memory

/// BCD's memory trick, upstream's donor pool: the MadeiraMemoryHost extension creates
/// memory and exits, and memory owned by a task that has exited counts against nobody,
/// so the game's data can live outside the app's iOS limit at RAM speed. It is off in
/// upstream until you set a size. Here it starts on, sized by the device. A device that
/// has little memory to spare gets less, and the guard stops taking it under pressure,
/// because taking too much is what froze an iPhone 16e running a large game.
enum GlassMemory {
    private static let appliedKey = "madeiraGlassMemoryApplied"
    private static let choiceKey = "madeiraGlassMemoryChoice"
    static var deviceGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    static var automatic: Int {
        switch deviceGB {
        case ..<5: return 0
        case ..<7: return 1024
        case ..<9.5: return 2048
        case ..<13: return 3072
        default: return 4096
        }
    }

    /// The choices Settings and the quick menu step through, with their labels.
    static let values = [-1, 0, 1024, 2048, 3072, 4096]
    static let labels = ["Auto", "Off", "1 GB", "2 GB", "3 GB", "4 GB"]

    /// -1 is Auto, 0 off, otherwise megabytes.
    static var choice: Int {
        get { UserDefaults.standard.object(forKey: choiceKey) as? Int ?? -1 }
        set {
            UserDefaults.standard.set(newValue, forKey: choiceKey)
            write(newValue < 0 ? automatic : newValue)
        }
    }

    private static func write(_ megabytes: Int) {
        _ = MadeiraConfig.set("donor-pool-mb", megabytes > 0 ? String(megabytes) : nil)
    }

    /// Once per install, and never over a size someone set by hand.
    static func applyDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: appliedKey) else { return }
        UserDefaults.standard.set(true, forKey: appliedKey)
        if MadeiraConfig.get("donor-pool-mb") == nil { write(automatic) }
        if MadeiraConfig.get("donor-pool-guard") == nil { _ = MadeiraConfig.set("donor-pool-guard", "1") }
        LogStore.shared.log("[glass-memory] device=\(String(format: "%.1f", deviceGB)) GB donor-pool-mb=\(MadeiraConfig.get("donor-pool-mb") ?? "0")")
    }
}
