// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Glass: the home interface. Home, Library, Store and Settings in Liquid Glass,
// landscape, and every part of it works from a controller. Library.swift's LibraryView
// stays as "Classic settings", and its detail pages open as sheets.

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

extension View {
    /// Liquid Glass; a material before iOS 26.
    @ViewBuilder func glassSurface(radius: CGFloat, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            self.glassEffect(glass.interactive(interactive), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

struct GlassButtonStyle: ButtonStyle {
    var compact = false
    var primary = false
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        let filled = primary || selected
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: filled ? .bold : .semibold))
            .foregroundStyle(filled ? Color.black : Color.white)
            .padding(.horizontal, compact ? 12 : 18).frame(minHeight: compact ? 38 : 44)
            .background { if filled { Capsule().fill(.white) } }
            .modifier(GlassButtonSurface(on: !filled))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
private struct GlassButtonSurface: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.glassSurface(radius: 22, interactive: true) } else { content }
    }
}

struct GlassFocusRing: View {
    var radius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: radius + 3, style: .continuous).stroke(.white, lineWidth: 2)
            .padding(-3).allowsHitTesting(false)
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
    var subtitle: String {
        if let transfer { return source.rawValue + " · " + transfer }
        return source.rawValue + " · " + (installed ? "Ready to play" : "Not installed")
    }
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

/// The screen-filling art behind everything, cross-fading as the selection moves.
struct GlassBackdrop: View {
    let game: GlassGame?
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.03, green: 0.03, blue: 0.045)
                if let game {
                    Group {
                        if let hero = game.hero {
                            AsyncImage(url: hero) { image in image.resizable().scaledToFill() } placeholder: { GlassCover(game: game).blur(radius: 24) }
                        } else if let entry = game.entry, entry.steamID != nil || entry.steamAppID != nil {
                            LibraryArtwork(entry: entry, backdrop: true)
                        } else {
                            GlassCover(game: game).blur(radius: 24).opacity(0.85)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                    .id(game.id).transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: game?.id)
    }
}

// MARK: - Rows

struct GlassRow: Identifiable {
    enum Kind {
        case toggle(Bool, (Bool) -> Void)
        case choice([String], Int, (Int) -> Void)
        case info(String)
        case action(String?, () -> Void)
    }
    var id: String { title }
    var title: String
    var detail: String?
    var kind: Kind
}

struct GlassRowView: View {
    let row: GlassRow
    let focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 15, weight: .medium))
                if let detail = row.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            switch row.kind {
            case .toggle(let on, let change):
                Toggle("", isOn: Binding(get: { on }, set: change)).labelsHidden()
            case .choice(let options, let selected, let pick):
                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { index in
                        Button(options[index]) { pick(index) }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(index == selected ? .black : .white)
                            .padding(.horizontal, 12).frame(height: 38)
                            .background { if index == selected { Capsule().fill(.white) } }
                    }
                }.background(.white.opacity(0.1), in: Capsule())
            case .info(let value):
                Text(value).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
            case .action(let label, let run):
                Button(action: run) {
                    HStack(spacing: 4) {
                        if let label { Text(label).font(.system(size: 14)) }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }.foregroundStyle(.white.opacity(0.8)).frame(minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 52)
        .background { if focused { RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.14)) } }
        .overlay { if focused { RoundedRectangle(cornerRadius: 14).stroke(.white, lineWidth: 1.5) } }
        .contentShape(Rectangle())
    }
}

extension GlassRow {
    /// The controller's accept and left/right on a row.
    func accept() {
        switch kind {
        case .toggle(let on, let change): change(!on)
        case .choice(let options, let selected, let pick): pick((selected + 1) % options.count)
        case .action(_, let run): run()
        case .info: break
        }
    }
    func step(_ delta: Int) {
        if case .choice(let options, let selected, let pick) = kind {
            let next = selected + delta
            if options.indices.contains(next) { pick(next) }
        }
    }
}

// MARK: - Root

enum GlassTab: String, CaseIterable, Identifiable {
    case home = "Home", library = "Library", store = "Store", settings = "Settings"
    var id: String { rawValue }
}

enum GlassOverlay: Equatable {
    case details(String), search, downloads, importer, storeItem(String), controllerTest
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
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab = GlassTab.home
    @State private var overlay: GlassOverlay?
    @State private var sheet: GlassSheet?
    @State private var selectedID: String?
    /// Where the controller is on the home page: 0 top bar, 1 covers, 2 Play and Details.
    @State private var homeZone = 1
    @State private var homeButton = 0
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
    @State private var storeQuery = ""
    @State private var searchText = ""
    @State private var searchFocus = 0
    @State private var settingsCategory = 0
    @State private var settingsFocus = -1
    @State private var overlayFocus = 0
    @State private var opening: (game: GlassGame, frame: CGRect)?
    @State private var openingGrown = false
    @State private var selectedFrame = CGRect.zero
    @State private var picking = false
    @State private var revision = 0

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

    private var homeGames: [GlassGame] { Array(games.prefix(6)) }
    private var selected: GlassGame? {
        let list = games
        return list.first { $0.id == selectedID } ?? list.first
    }
    private var libraryGames: [GlassGame] {
        let filter = ["All", "Steam", "Epic", "GOG", "Imported"][libraryFilter]
        return filter == "All" ? games : games.filter { $0.source.rawValue == filter }
    }

    var body: some View {
        ZStack {
            GlassBackdrop(game: selected)
            if tab != .home {
                Rectangle().fill(.black.opacity(0.6)).ignoresSafeArea().transition(.opacity)
            } else {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .leading, endPoint: .init(x: 0.6, y: 0.5))
                    .ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 8) {
                topBar
                page.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 8)
            VStack {
                Spacer()
                HStack { Spacer(); GlassHints(items: hints) }
            }.padding(.bottom, 6).opacity(overlay == .controllerTest ? 0 : 1)
            overlayLayer
            openingLayer
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $onboarding.presented) { OnboardingView() }
        .sheet(item: $sheet, onDismiss: { revision += 1; refreshStores() }) { sheetView($0) }
        .fileImporter(isPresented: $picking, allowedContentTypes: GlassImporter.pickerTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach { importer.start($0, scoped: true) } }
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
            Text("There isn't room for this RAR and the game at once, so Madeira will free the archive as it unpacks. Keep the app open. If it stops partway, the archive can't be used again and you'd need a new copy.")
        }
        .onAppear(perform: appeared)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { steamGames.refresh(); if SteamOwnedLibrary.enabled { steam.reconcileSession() } }
        }
        .onChange(of: tab) { _, next in if next == .store { loadStore() } }
        .onChange(of: store) { _, _ in shelves = []; storeResults = nil; storeFocus = (-1, 0); loadStore() }
        .onReceive(LibraryController.shared.commands) { handle($0) }
    }

    private func appeared() {
        EndedSessionSurface.install(); EndedSessionSurface.hide(reason: "library-appeared")
        onboarding.presentIfNeeded()
        steamGames.refresh()
        if SteamOwnedLibrary.enabled { steam.start(); steam.reconcileSession() }
        if EpicLibrary.enabled { epic.start() }
        if GOGLibrary.enabled { gog.start() }
        GlassMemory.applyDefaultsIfNeeded()
        LogStore.shared.log("[glass] home games=\(games.count) pads=\(pads.pads.count)")
    }

    private func refreshStores() {
        Task {
            if SteamOwnedLibrary.enabled, steam.signedIn { await steam.refreshLibrary(interactive: false) }
            if epic.signedIn { await epic.refreshLibrary(interactive: false) }
            if gog.signedIn { await gog.refreshLibrary(interactive: false) }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Text("Madeira").font(.system(size: 20, weight: .bold)).frame(width: 120, alignment: .leading)
            Spacer()
            HStack(spacing: 0) {
                ForEach(GlassTab.allCases) { item in
                    Button(item.rawValue) { switchTab(item) }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item == tab ? .black : .white)
                        .frame(width: 84, height: 36)
                        .background { if item == tab { Capsule().fill(.white) } }
                }
            }
            .padding(3)
            .glassSurface(radius: 22)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tab)
            Spacer()
            HStack(spacing: 8) {
                iconButton("magnifyingglass", "Search", focused: tab == .home && homeZone == 0 && topButton == 0) { overlay = .search; searchText = "" }
                iconButton("arrow.down.to.line", "Downloads", focused: tab == .home && homeZone == 0 && topButton == 1, badge: hasTransfers) { overlay = .downloads; overlayFocus = 0 }
            }.frame(width: 120, alignment: .trailing)
        }.frame(height: 44)
    }

    private func iconButton(_ symbol: String, _ label: String, focused: Bool, badge: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) { if badge { Circle().fill(Color.accentColor).frame(width: 9, height: 9).padding(9) } }
        }
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
        withAnimation(.easeInOut(duration: 0.22)) { tab = next }
    }

    private var hints: [(GlassPadButton, String)] {
        if overlay != nil { return [(.accept, "Select"), (.back, "Close")] }
        switch tab {
        case .home: return [(.accept, "Open"), (.action, "Details"), (.add, "Search"), (.tabLeft, "Tabs"), (.tabRight, "")]
        case .library: return [(.accept, "Open"), (.action, "Import"), (.add, "Search")]
        case .store: return [(.accept, "Open"), (.action, "Store site"), (.add, "Search")]
        case .settings: return [(.accept, "Select"), (.back, "Back")]
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
                    HStack {
                        Button("Import") { overlay = .importer; overlayFocus = 0 }.buttonStyle(GlassButtonStyle(primary: true))
                        Button("Store") { switchTab(.store) }.buttonStyle(GlassButtonStyle())
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollViewReader { reader in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(list) { game in cover(game) }
                                Button { switchTab(.library) } label: {
                                    Text("All\ngames").font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                                        .frame(width: 76, height: 114)
                                }.glassSurface(radius: 12, interactive: true)
                            }.padding(6).frame(height: 192)
                        }
                        .onChange(of: selectedID) { _, id in withAnimation { reader.scrollTo(id, anchor: .center) } }
                    }
                    if let game = selected { homeInfo(game) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func cover(_ game: GlassGame) -> some View {
        let on = game.id == selected?.id
        return Button {
            if on { open(game) } else { select(game) }
        } label: {
            GlassCover(game: game)
                .frame(width: on ? 120 : 76, height: on ? 180 : 114)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(on ? 1 : 0.8)
                .shadow(color: .black.opacity(on ? 0.45 : 0), radius: 15, y: 10)
                .overlay { if on && homeZone == 1 { GlassFocusRing(radius: 12) } }
                .overlay(alignment: .bottom) {
                    if let progress = game.progress {
                        ProgressView(value: progress).tint(.white).padding(6)
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
    }

    private func select(_ game: GlassGame) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { selectedID = game.id }
    }

    private func homeInfo(_ game: GlassGame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(game.title).font(.system(size: 22, weight: .bold)).lineLimit(1)
            Text(game.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.88))
            HStack(spacing: 8) {
                Button(primaryLabel(game)) { open(game) }
                    .buttonStyle(GlassButtonStyle(primary: true))
                    .overlay { if homeZone == 2 && homeButton == 0 { GlassFocusRing(radius: 22) } }
                Button("Details") { overlay = .details(game.id); overlayFocus = 0 }
                    .buttonStyle(GlassButtonStyle())
                    .overlay { if homeZone == 2 && homeButton == 1 { GlassFocusRing(radius: 22) } }
            }.padding(.top, 8)
        }
        .id(game.id).transition(.opacity.combined(with: .offset(y: 6)))
        .animation(.easeOut(duration: 0.3), value: game.id)
    }

    private func primaryLabel(_ game: GlassGame) -> String {
        if game.installed { return "Play" }
        return game.transfer ?? "Install"
    }

    /// Play, or start the download.
    private func open(_ game: GlassGame) {
        guard let entry = game.entry else { install(game); return }
        guard !UIAccessibility.isReduceMotionEnabled, selectedFrame != .zero, tab == .home, overlay == nil else { play(entry); return }
        opening = (game, selectedFrame)
        openingGrown = false
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.56)) { openingGrown = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            play(entry)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { opening = nil; openingGrown = false }
        }
    }

    private func install(_ game: GlassGame) {
        if game.transfer != nil { overlay = .downloads; overlayFocus = 0; return }
        switch game.source {
        case .steam: if let id = game.steamID { steam.install(id) }
        case .epic: if let key = game.storeKey { epic.install(key) }
        case .gog: if let key = game.storeKey { gog.install(key) }
        case .imported: break
        }
    }

    @ViewBuilder private var openingLayer: some View {
        if let opening {
            GeometryReader { geo in
                let full = geo.frame(in: .global)
                let start = opening.frame
                ZStack {
                    GlassCover(game: opening.game)
                    GlassBackdrop(game: opening.game).opacity(openingGrown ? 1 : 0)
                }
                .frame(width: openingGrown ? full.width : start.width, height: openingGrown ? full.height : start.height)
                .clipShape(RoundedRectangle(cornerRadius: openingGrown ? 0 : 12, style: .continuous))
                .position(x: (openingGrown ? full.midX : start.midX) - full.minX, y: (openingGrown ? full.midY : start.midY) - full.minY)
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
        }
    }

    // MARK: Library

    private var library: some View {
        let list = libraryGames
        let filters = ["All", "Steam", "Epic", "GOG", "Imported"]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 0) {
                    ForEach(filters.indices, id: \.self) { index in
                        Button(filters[index]) { libraryFilter = index; libraryFocus = 0 }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(index == libraryFilter ? .black : .white)
                            .padding(.horizontal, 14).frame(height: 38)
                            .background { if index == libraryFilter { Capsule().fill(.white) } }
                    }
                }.padding(3).glassSurface(radius: 22)
                    .overlay { if libraryZone == 0 { GlassFocusRing(radius: 22) } }
                Spacer()
                Button("Import") { overlay = .importer; overlayFocus = 0 }.buttonStyle(GlassButtonStyle())
            }
            if list.isEmpty {
                Text("Nothing here yet").font(.system(size: 15)).foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 14) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, game in
                                Button { selectedID = game.id; overlay = .details(game.id); overlayFocus = 0 } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        GlassCover(game: game).aspectRatio(2 / 3, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay { if libraryZone == 1 && index == libraryFocus { GlassFocusRing(radius: 12) } }
                                        Text(game.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        Text(game.transfer ?? game.source.rawValue).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                                    }
                                }.buttonStyle(.plain).id(index)
                            }
                        }.padding(6)
                    }
                    .onChange(of: libraryFocus) { _, index in withAnimation { reader.scrollTo(index, anchor: .center) } }
                }
            }
        }
    }

    // MARK: Store

    private var signedIn: Bool {
        switch store {
        case .steam: return SteamSignIn.isSignedIn
        case .epic: return epic.signedIn
        case .gog: return gog.signedIn
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(GlassStoreKind.allCases) { kind in
                        Button(kind.rawValue) { store = kind }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(kind == store ? .black : .white)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background { if kind == store { Capsule().fill(.white) } }
                    }
                }.padding(3).glassSurface(radius: 22)
                    .overlay { if storeFocus.shelf == -1 { GlassFocusRing(radius: 22) } }
                if signedIn {
                    TextField("Search \(store.rawValue)", text: $storeQuery)
                        .font(.system(size: 14)).padding(.horizontal, 14).frame(height: 44)
                        .glassSurface(radius: 22).frame(maxWidth: 240)
                        .onSubmit(runStoreSearch)
                    Spacer()
                    Button("Store site") { sheet = .web(store.rawValue, store.home) }.buttonStyle(GlassButtonStyle())
                }
            }
            if !signedIn {
                VStack(spacing: 10) {
                    Text("Sign in to shop on \(store.rawValue)").font(.system(size: 20, weight: .bold))
                    Text("Games you buy or claim join your library, and Madeira downloads them.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.82))
                    Button("Sign in") { sheet = .signIn(store) }.buttonStyle(GlassButtonStyle(primary: true))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if storeLoading && visibleShelves.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleShelves.isEmpty {
                VStack(spacing: 10) {
                    Text(store == .epic ? "Epic's full catalogue is on its site" : "The store didn't answer").font(.system(size: 16, weight: .semibold))
                    Button("Open \(store.rawValue)") { sheet = .web(store.rawValue, store.home) }.buttonStyle(GlassButtonStyle(primary: true))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(visibleShelves.enumerated()), id: \.element.id) { row, shelf in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(shelf.title).font(.system(size: 15, weight: .bold))
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(Array(shelf.items.enumerated()), id: \.element.id) { column, item in
                                                storeTile(item, focused: storeFocus.shelf == row && storeFocus.item == column)
                                                    .id("\(row)-\(column)")
                                            }
                                        }.padding(6)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: storeFocus.shelf) { _, _ in scrollStore(reader) }
                    .onChange(of: storeFocus.item) { _, _ in scrollStore(reader) }
                }
            }
        }
    }

    private func scrollStore(_ reader: ScrollViewProxy) {
        withAnimation { reader.scrollTo("\(storeFocus.shelf)-\(storeFocus.item)", anchor: .center) }
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

    private func storeTile(_ item: GlassStoreItem, focused: Bool) -> some View {
        Button { storeItem = item; overlay = .storeItem(item.id); overlayFocus = 0 } label: {
            VStack(alignment: .leading, spacing: 3) {
                AsyncImage(url: item.image) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                    .frame(width: 96, height: 144).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { if focused { GlassFocusRing(radius: 10) } }
                Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(item.price).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            }.frame(width: 96)
        }.buttonStyle(.plain)
    }

    private func owned(_ item: GlassStoreItem) -> GlassGame? {
        switch item.store {
        case .steam: return games.first { $0.steamID == Int(item.key) }
        case .gog: return games.first { $0.source == .gog && $0.storeKey == item.key }
        case .epic: return games.first { $0.source == .epic && $0.title.caseInsensitiveCompare(item.name) == .orderedSame }
        }
    }

    // MARK: Settings

    private let categories = ["Accounts", "Controllers", "Memory", "JIT", "Storage", "Interface"]

    private func openTest() { overlay = .controllerTest }

    private var settingsRows: [GlassRow] {
        _ = revision
        switch settingsCategory {
        case 0:
            return [
                GlassRow(title: "Steam", kind: .action(SteamSignIn.accountName ?? "Sign in") { sheet = .signIn(.steam) }),
                GlassRow(title: "Epic Games", kind: .action(epic.accountName ?? (epic.signedIn ? "Signed in" : "Sign in")) { sheet = .signIn(.epic) }),
                GlassRow(title: "GOG", kind: .action(gog.accountName ?? (gog.signedIn ? "Signed in" : "Sign in")) { sheet = .signIn(.gog) })
            ]
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
            let values = [-1, 0, 1024, 2048, 3072, 4096]
            let current = GlassMemory.choice
            return [
                GlassRow(title: "Memory saver",
                         detail: "Keeps game memory outside Madeira's iOS limit, which lets bigger games run. Applies at the next game start.",
                         kind: .choice(["Auto", "Off", "1 GB", "2 GB", "3 GB", "4 GB"], values.firstIndex(of: current) ?? 0) { index in
                    GlassMemory.choice = values[index]
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
            return [GlassRow(title: "JIT", detail: "Games need JIT to run.", kind: jitState.enabled ? .info("Enabled") : .action("Enable") { enableJIT() })]
        case 4:
            let formatter = ByteCountFormatter()
            let installed = model.entries.compactMap(\.folderBytes).reduce(0, +)
            return [GlassRow(title: "Free storage", kind: .info(formatter.string(fromByteCount: GlassImporter.freeBytes()))),
                    GlassRow(title: "Games", kind: .info(formatter.string(fromByteCount: installed)))]
        default:
            return [
                GlassRow(title: "All settings", detail: "Madeira's full settings, including graphics and diagnostics.", kind: .action(nil) { sheet = .classicSettings }),
                GlassRow(title: "Glass interface", detail: "Off returns to the classic library at the next start.", kind: .toggle(GlassUI.enabled) { on in
                    UserDefaults.standard.set(on, forKey: GlassUI.key)
                    revision += 1
                })
            ]
        }
    }

    private func padName(_ pad: GCController) -> String {
        switch GlassPadFamily.of(pad) {
        case .playStation: return "PlayStation"
        case .xbox: return "Xbox"
        case .generic: return "Controller"
        }
    }

    private var settings: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                ForEach(categories.indices, id: \.self) { index in
                    Button { settingsCategory = index; settingsFocus = -1 } label: {
                        Text(categories[index]).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(index == settingsCategory ? .black : .white)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14)
                            .background { if index == settingsCategory { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white) } }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(5).frame(width: 186).glassSurface(radius: 22)
            .overlay { if settingsFocus < 0 && overlay == nil { GlassFocusRing(radius: 22) } }
            let rows = settingsRows
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(categories[settingsCategory]).font(.system(size: 19, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 4)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            GlassRowView(row: row, focused: settingsFocus == index).id(index)
                        }
                    }.padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).glassSurface(radius: 22)
                .onChange(of: settingsFocus) { _, index in withAnimation { reader.scrollTo(index, anchor: .center) } }
            }
        }.padding(.bottom, 8)
    }

    // MARK: Overlays

    @ViewBuilder private var overlayLayer: some View {
        if let overlay {
            Button { close() } label: { Color.black.opacity(0.38).ignoresSafeArea() }
                .buttonStyle(.plain).accessibilityLabel("Close").transition(.opacity)
            Group {
                switch overlay {
                case .details(let id): if let game = games.first(where: { $0.id == id }) { detailsCard(game) }
                case .search: searchCard
                case .downloads: downloadsCard
                case .importer: importCard
                case .storeItem: if let storeItem { storeItemCard(storeItem) }
                case .controllerTest: GlassControllerTest(close: { self.overlay = nil })
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 10)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func close() { withAnimation(.easeOut(duration: 0.18)) { overlay = nil } }

    private func detailsActions(_ game: GlassGame) -> [(String, () -> Void)] {
        var list: [(String, () -> Void)] = [(primaryLabel(game), { close(); open(game) })]
        if let entry = game.entry { list.append(("Game settings", { sheet = .gameSettings(entry) })) }
        return list
    }

    private func detailsCard(_ game: GlassGame) -> some View {
        let actions = detailsActions(game)
        return HStack(spacing: 18) {
            GlassCover(game: game).frame(width: 170, height: 255).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(game.title).font(.system(size: 24, weight: .bold)).lineLimit(2)
                Text(game.subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.82))
                if let bytes = game.entry?.folderBytes {
                    Text(ByteCountFormatter().string(fromByteCount: bytes)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.82))
                }
                if let progress = game.progress { ProgressView(value: progress).tint(.white) }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(actions.indices, id: \.self) { index in
                        Button(actions[index].0) { actions[index].1() }
                            .buttonStyle(GlassButtonStyle(primary: index == 0))
                            .overlay { if index == overlayFocus { GlassFocusRing(radius: 22) } }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18).frame(maxWidth: 580, maxHeight: 295).glassSurface(radius: 30)
    }

    private var searchResults: [GlassGame] {
        let list = games
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? list : list.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var searchCard: some View {
        let results = searchResults
        return VStack(spacing: 4) {
            TextField("Search games", text: $searchText).font(.system(size: 16)).frame(height: 44).padding(.horizontal, 6)
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, game in
                            Button { selectedID = game.id; overlay = .details(game.id); overlayFocus = 0 } label: {
                                HStack(spacing: 12) {
                                    GlassCover(game: game).frame(width: 32, height: 46).clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading) {
                                        Text(game.title).font(.system(size: 15, weight: .medium))
                                        Text(game.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                                    }
                                    Spacer()
                                }
                                .padding(6)
                                .background { if index == searchFocus { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.14)) } }
                            }.buttonStyle(.plain).id(index)
                        }
                        if results.isEmpty {
                            Text("No games match that name").font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).padding(30)
                        }
                    }
                }
                .onChange(of: searchFocus) { _, index in withAnimation { reader.scrollTo(index, anchor: .center) } }
            }
        }
        .padding(12).frame(maxWidth: 480, maxHeight: 340).glassSurface(radius: 28)
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

    private var downloadsCard: some View {
        let list = transfers
        return VStack(alignment: .leading, spacing: 10) {
            Text("Downloads").font(.system(size: 18, weight: .bold))
            if list.isEmpty {
                Text("Nothing downloading. Install a game from the Store or import one, and it shows up here.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                    ProgressView(value: min(1, item.fraction)).tint(.white)
                                    Text(item.status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(3)
                                }
                                Button(item.stopLabel, action: item.stop).buttonStyle(GlassButtonStyle(compact: true))
                                    .overlay { if index == overlayFocus { GlassFocusRing(radius: 19) } }
                            }
                        }
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: 420, maxHeight: 300, alignment: .topLeading).glassSurface(radius: 28)
    }

    private var importChoices: [(String, () -> Void)] {
        var list: [(String, () -> Void)] = [("Choose from Files", { picking = true })]
        for url in GlassImporter.waitingArchives().prefix(4) {
            list.append((url.lastPathComponent, { importer.start(url, scoped: false); overlay = .downloads; overlayFocus = 0 }))
        }
        return list
    }

    private var importCard: some View {
        let choices = importChoices
        return VStack(alignment: .leading, spacing: 8) {
            Text("Import a game").font(.system(size: 20, weight: .bold))
            Text("A folder, a program, or a .zip, .rar or .7z. Archives unpack into Madeira and are removed afterwards, freeing their space as they go when storage is tight.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            ForEach(choices.indices, id: \.self) { index in
                Button(choices[index].0) { choices[index].1() }
                    .buttonStyle(GlassButtonStyle(primary: index == 0))
                    .lineLimit(1)
                    .overlay { if index == overlayFocus { GlassFocusRing(radius: 22) } }
            }
        }
        .padding(18).frame(maxWidth: 440).glassSurface(radius: 28)
    }

    private func storeActions(_ item: GlassStoreItem) -> [(String, () -> Void)] {
        var list: [(String, () -> Void)] = []
        if let game = owned(item) {
            list.append((game.installed ? "In your library" : primaryLabel(game), {
                overlay = .details(game.id); overlayFocus = 0
                if !game.installed { install(game) }
            }))
        } else {
            let label = item.price == "Free" ? "Add to library" : "Buy for \(item.price)"
            list.append((label, { let page = item.page; overlay = nil; sheet = .web(item.name, page) }))
        }
        list.append(("Store page", { let page = item.page; overlay = nil; sheet = .web(item.name, page) }))
        return list
    }

    private func storeItemCard(_ item: GlassStoreItem) -> some View {
        let actions = storeActions(item)
        return HStack(spacing: 18) {
            AsyncImage(url: item.image) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                .frame(width: 170, height: 255).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.system(size: 24, weight: .bold)).lineLimit(3)
                Text("\(item.store.rawValue) · \(item.price)").font(.system(size: 14)).foregroundStyle(.white.opacity(0.82))
                Text("Check how well a game runs before you buy: not every Windows game works in Madeira.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                Spacer()
                HStack(spacing: 8) {
                    ForEach(actions.indices, id: \.self) { index in
                        Button(actions[index].0) { actions[index].1() }
                            .buttonStyle(GlassButtonStyle(primary: index == 0))
                            .overlay { if index == overlayFocus { GlassFocusRing(radius: 22) } }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18).frame(maxWidth: 580, maxHeight: 295).glassSurface(radius: 30)
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
        guard sheet == nil, !picking, !onboarding.presented, opening == nil else { return }
        if overlay == .controllerTest { return }
        if let overlay { handleOverlay(overlay, command); return }
        switch command {
        case "tabLeft", "tabRight":
            let all = GlassTab.allCases
            let index = all.firstIndex(of: tab) ?? 0
            let next = (index + (command == "tabLeft" ? all.count - 1 : 1)) % all.count
            switchTab(all[next])
            return
        case "add":
            if tab == .store, signedIn { sheet = .web(store.rawValue, store.home) } else { overlay = .search; searchText = ""; searchFocus = 0 }
            return
        case "menu":
            overlay = .downloads; overlayFocus = 0
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
            if command == "accept" { overlay = .importer; overlayFocus = 0 }
            return
        }
        let index = list.firstIndex { $0.id == selected?.id } ?? 0
        switch (homeZone, command) {
        case (0, "left"): topButton = 0
        case (0, "right"): topButton = 1
        case (0, "down"): homeZone = 1
        case (0, "accept"):
            if topButton == 0 { overlay = .search; searchText = ""; searchFocus = 0 } else { overlay = .downloads; overlayFocus = 0 }
        case (1, "left"): if index > 0 { select(list[index - 1]) }
        case (1, "right"):
            if index + 1 < list.count { select(list[index + 1]) } else { switchTab(.library) }
        case (1, "up"): homeZone = 0
        case (1, "down"): homeZone = 2; homeButton = 0
        case (1, "accept"): if let game = selected { open(game) }
        case (1, "action"): if let game = selected { overlay = .details(game.id); overlayFocus = 0 }
        case (2, "left"): homeButton = 0
        case (2, "right"): homeButton = 1
        case (2, "up"), (2, "back"): homeZone = 1
        case (2, "accept"):
            guard let game = selected else { return }
            if homeButton == 0 { open(game) } else { overlay = .details(game.id); overlayFocus = 0 }
        default: break
        }
    }

    private func handleLibrary(_ command: String) {
        let list = libraryGames
        if libraryZone == 0 {
            switch command {
            case "left": libraryFilter = max(0, libraryFilter - 1); libraryFocus = 0
            case "right": libraryFilter = min(4, libraryFilter + 1); libraryFocus = 0
            case "down", "accept": libraryZone = 1
            case "action": overlay = .importer; overlayFocus = 0
            default: break
            }
            return
        }
        switch command {
        case "left": libraryFocus = max(0, libraryFocus - 1)
        case "right": libraryFocus = min(max(0, list.count - 1), libraryFocus + 1)
        case "up": if libraryFocus >= 6 { libraryFocus -= 6 } else { libraryZone = 0 }
        case "down": libraryFocus = min(max(0, list.count - 1), libraryFocus + 6)
        case "accept":
            if list.indices.contains(libraryFocus) {
                selectedID = list[libraryFocus].id
                overlay = .details(list[libraryFocus].id); overlayFocus = 0
            }
        case "action": overlay = .importer; overlayFocus = 0
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
            case "down": if signedIn, !rows.isEmpty { storeFocus = (0, 0) }
            case "accept": if !signedIn { sheet = .signIn(store) } else if rows.isEmpty { sheet = .web(store.rawValue, store.home) }
            case "action": sheet = .web(store.rawValue, store.home)
            case "back": switchTab(.home)
            default: break
            }
            return
        }
        guard rows.indices.contains(storeFocus.shelf) else { storeFocus = (-1, 0); return }
        let row = rows[storeFocus.shelf]
        switch command {
        case "left": storeFocus.item = max(0, storeFocus.item - 1)
        case "right": storeFocus.item = min(row.items.count - 1, storeFocus.item + 1)
        case "up": storeFocus = storeFocus.shelf == 0 ? (-1, 0) : (storeFocus.shelf - 1, 0)
        case "down": if storeFocus.shelf + 1 < rows.count { storeFocus = (storeFocus.shelf + 1, 0) }
        case "accept":
            if row.items.indices.contains(storeFocus.item) {
                let item = row.items[storeFocus.item]
                storeItem = item; overlay = .storeItem(item.id); overlayFocus = 0
            }
        case "action": sheet = .web(store.rawValue, store.home)
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
            if rows.indices.contains(settingsFocus), case .choice(_, let selected, _) = rows[settingsFocus].kind, selected > 0 {
                rows[settingsFocus].step(-1)
            } else { settingsFocus = -1 }
        case "right": if rows.indices.contains(settingsFocus) { rows[settingsFocus].step(1) }
        case "accept": if rows.indices.contains(settingsFocus) { rows[settingsFocus].accept() }
        case "back": settingsFocus = -1
        default: break
        }
    }

    private func handleOverlay(_ overlay: GlassOverlay, _ command: String) {
        if command == "back" { close(); return }
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
            case "left": move(actions.count, -1)
            case "right": move(actions.count, 1)
            case "accept": if actions.indices.contains(overlayFocus) { actions[overlayFocus].1() }
            default: break
            }
        case .search:
            let results = searchResults
            switch command {
            case "up": searchFocus = max(0, searchFocus - 1)
            case "down": searchFocus = min(max(0, results.count - 1), searchFocus + 1)
            case "accept":
                if results.indices.contains(searchFocus) {
                    selectedID = results[searchFocus].id
                    self.overlay = .details(results[searchFocus].id); overlayFocus = 0
                }
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
