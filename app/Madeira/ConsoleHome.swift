import SwiftUI
import Combine
import GameController
import UIKit

/// The console home: a full-screen, controller-first front end in the style of
/// a game console's dashboard, in place of the library's tab view
/// (LibraryView). A top bar of tabs (LB/RB) over Home (a hero for the focused
/// game and a carousel), Library (every game in a grid), Steam (the library's
/// Steam section, by touch) and Settings (categories on the left, their
/// options on the right). Everything moves with the D-pad or left stick
/// (LibraryController's commands, with hold-to-repeat) and works by touch.
///
/// The choice is stored under `key` (on by default); Settings in either front
/// end turns it off or on, and ContentView swaps the two at once.
enum ConsoleHome {
    static let key = "madeiraConsoleHome"
    static let accentKey = "madeiraConsoleAccent"
    static let accents: [(name: String, color: Color)] = [
        ("Green", Color(red: 0.20, green: 0.90, blue: 0.55)),
        ("Blue", Color(red: 0.25, green: 0.62, blue: 1.00)),
        ("Purple", Color(red: 0.66, green: 0.47, blue: 1.00)),
        ("Orange", Color(red: 1.00, green: 0.58, blue: 0.20)),
        ("Red", Color(red: 1.00, green: 0.33, blue: 0.38)),
    ]
    static func accent(_ index: Int) -> Color { accents[min(max(index, 0), accents.count - 1)].color }
    static let background = Color(red: 0.035, green: 0.043, blue: 0.063)
}

enum ConsoleTab: Int, Identifiable {
    case home, library, steam, settings
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .steam: return "Steam"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.grid.3x3.fill"
        case .steam: return "cloud.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ConsoleHomeView: View {
    var play: (LibraryEntry) -> Void
    var enableJIT: () -> Void
    var startDock: (DockGame, Bool) -> Void = { _, _ in }
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var steamGames = SteamGamesModel.shared
    @ObservedObject private var onboarding = OnboardingModel.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ConsoleHome.accentKey) private var accentIndex = 0
    @State private var tab: ConsoleTab = .home
    /// Desktop, the games you added and installed Steam games, last played first.
    @State private var games: [LibraryEntry] = []
    /// Focus on Home and in Library; `games.count` is the Add game tile.
    @State private var homeIndex = 0
    @State private var libraryIndex = 0
    @State private var libraryColumns = 4
    @State private var selected: LibraryEntry?
    @State private var browser = false
    /// Settings has a sheet of its own up.
    @State private var settingsModal = false
    /// Settings' focus is on the options (1) or the categories (0), for the hints.
    @State private var settingsColumn = 0

    private var accent: Color { ConsoleHome.accent(accentIndex) }
    private var tabs: [ConsoleTab] {
        (MadeiraDock.enabled || SteamSettingsSection.shown) ? [.home, .library, .steam, .settings] : [.home, .library, .settings]
    }
    private var modal: Bool { selected != nil || browser || onboarding.presented || settingsModal || model.error != nil }
    private var jitProblem: JITCoordinator.ConnectionProblem? {
        jit.connectionProblem.flatMap { model.error == $0.message ? $0 : nil }
    }
    private var focusedEntry: LibraryEntry? {
        let index = tab == .library ? libraryIndex : homeIndex
        return games.indices.contains(index) ? games[index] : nil
    }

    var body: some View {
        ZStack {
            ConsoleBackdrop(entry: tab == .home || tab == .library ? focusedEntry : nil, accent: accent)
            VStack(spacing: 0) {
                ConsoleTopBar(tabs: tabs, tab: tab, accent: accent) { switchTab(to: $0) }
                    .padding(.horizontal, 24).padding(.top, 10)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                ConsoleHintBar(hints: hints).padding(.horizontal, 24).padding(.bottom, 10)
            }
        }
        .foregroundStyle(.white)
        .tint(accent)
        .preferredColorScheme(.dark)
        // Full screen: no navigation bar, status bar or home indicator.
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .alert(jitProblem == nil ? "Library" : "Couldn't Enable JIT",
               isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            if let jitProblem { jitConnectionActions(jitProblem, retry: enableJIT) { model.error = nil } }
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .fullScreenCover(isPresented: $onboarding.presented) { OnboardingView() }
        .sheet(isPresented: $browser) {
            NavigationStack { ExecutableBrowser(folder: LibraryModel.drive) { entry in
                model.save(entry); browser = false; selected = entry
            } }
        }
        .sheet(item: $selected) { entry in
            LibraryDetail(entry: entry, play: { profile in
                play(profile)
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    if selected?.id == entry.id, model.startingJIT != entry.id { selected = nil }
                }
            })
        }
        .onChange(of: model.current) { _, current in if current != nil { selected = nil } }
        .onChange(of: model.error) { _, error in if error != nil { selected = nil } }
        .onChange(of: model.restartNotice) { _, notice in if notice != nil { selected = nil } }
        .onChange(of: model.jitNotice) { _, notice in if notice != nil { selected = nil } }
        .onChange(of: model.cloudNotice) { _, notice in if notice != nil { selected = nil } }
        .onChange(of: jit.showSetup) { _, show in if show { selected = nil } }
        .onChange(of: model.showDetail) { _, id in
            guard let id else { return }
            model.showDetail = nil
            selected = model.entries.first { $0.id == id }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshFlag(); steamGames.refresh() } }
        .onReceive(model.$entries) { rebuildGames(entries: $0) }
        .onReceive(steamGames.$games) { rebuildGames(steam: $0) }
        .onReceive(LibraryController.shared.commands) { handle($0) }
        .onAppear {
            EndedSessionSurface.install(); EndedSessionSurface.hide(reason: "library-appeared")
            onboarding.presentIfNeeded()
            steamGames.refresh()
            rebuildGames()
            LogStore.shared.log("[console-home] shown games=\(games.count)")
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home:
            ConsoleHomeTab(games: games, index: homeIndex, accent: accent,
                           tap: { tapped($0, index: $homeIndex) },
                           play: { launch(at: homeIndex) }, details: { details(at: homeIndex) }, add: { browser = true })
                .transition(.opacity)
        case .library:
            ConsoleLibraryGrid(games: games, index: libraryIndex, accent: accent, columns: $libraryColumns,
                               tap: { tapped($0, index: $libraryIndex) })
                .transition(.opacity)
        case .steam:
            GeometryReader { geo in
                ScrollView {
                    SteamGamesSection(search: "", layout: "cards", sort: "played", width: geo.size.width - 48,
                                      part: .all, open: { selected = $0 })
                        .padding(.horizontal, 24).padding(.vertical, 16)
                }
                .refreshable { await SteamGamesSection.refresh() }
            }
            .transition(.opacity)
        case .settings:
            ConsoleSettingsPage(active: tab == .settings && selected == nil && !browser && !onboarding.presented && model.error == nil,
                                modal: $settingsModal, column: $settingsColumn, accent: accent,
                                enableJIT: enableJIT, startDock: startDock, addGame: { browser = true },
                                exit: { switchTab(to: .home) })
                .transition(.opacity)
        }
    }

    private var hints: [ConsoleHint] {
        var list: [ConsoleHint]
        switch tab {
        case .home, .library:
            let onAdd = (tab == .home ? homeIndex : libraryIndex) == games.count
            list = onAdd ? [ConsoleHint("A", "Add game")]
                         : [ConsoleHint("A", "Play"), ConsoleHint("X", "Details"), ConsoleHint("Y", "Add game")]
        case .steam:
            list = [ConsoleHint("B", "Home")]
        case .settings:
            list = settingsColumn == 0 ? [ConsoleHint("A", "Open"), ConsoleHint("B", "Home")]
                                       : [ConsoleHint("A", "Select"), ConsoleHint("◀▶", "Adjust"), ConsoleHint("B", "Back")]
        }
        list.append(ConsoleHint("LB RB", "Tabs"))
        if tab != .settings { list.append(ConsoleHint("☰", "Settings")) }
        return list
    }

    // MARK: Games

    private func rebuildGames(entries: [LibraryEntry]? = nil, steam: [DockGame]? = nil) {
        let entries = entries ?? model.entries
        let steam = steam ?? steamGames.games
        let desktop = entries.first { $0.desktop == true } ?? .desktopEntry
        var list = entries.filter { $0.desktop != true && $0.steamAppID == nil }
        if MadeiraDock.enabled {
            list += steam.filter(\.installed).map { game in
                entries.first { $0.steamAppID == game.id }.map { var e = $0; e.relativePath = game.library + "/common/" + game.installDir; return e }
                    ?? model.steamEntry(game)
            }
        }
        list.append(desktop)
        // Last played first; the never played after them by name, the Desktop last of those.
        list.sort { a, b in
            if a.lastPlayed != b.lastPlayed { return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast) }
            if (a.desktop == true) != (b.desktop == true) { return b.desktop == true }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        // Keep the focus on the same game when the order changes.
        let homeID = games.indices.contains(homeIndex) ? Self.key(games[homeIndex]) : nil
        let libraryID = games.indices.contains(libraryIndex) ? Self.key(games[libraryIndex]) : nil
        games = list
        homeIndex = homeID.flatMap { id in list.firstIndex { Self.key($0) == id } } ?? min(homeIndex, list.count)
        libraryIndex = libraryID.flatMap { id in list.firstIndex { Self.key($0) == id } } ?? min(libraryIndex, list.count)
    }

    /// A Steam game made up for the moment has a new id each time: it is known by its app.
    static func key(_ entry: LibraryEntry) -> String {
        entry.steamAppID.map { "steam-\($0)" } ?? entry.id.uuidString
    }

    private func launch(at index: Int) {
        guard games.indices.contains(index) else { browser = true; return }
        let entry = games[index]
        // A Steam game opens its details page, which checks its download and sign-in first.
        if entry.steamAppID != nil { selected = entry; return }
        LogStore.shared.log("[console-home] play \(entry.title)")
        model.save(entry); play(entry)
    }

    private func details(at index: Int) {
        guard games.indices.contains(index) else { browser = true; return }
        selected = games[index]
    }

    /// Touch: the first tap focuses a game, a tap on the focused one plays it.
    private func tapped(_ index: Int, index focus: Binding<Int>) {
        if focus.wrappedValue == index { launch(at: index) }
        else { withAnimation(Self.motion) { focus.wrappedValue = index } }
    }

    // MARK: Controller

    static var motion: Animation? { UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.28, dampingFraction: 0.82) }

    private func switchTab(to newTab: ConsoleTab) {
        guard newTab != tab else { return }
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)) { tab = newTab }
        if newTab == .settings { settingsColumn = 0 }
    }

    private func cycleTab(_ step: Int) {
        let index = tabs.firstIndex(of: tab) ?? 0
        switchTab(to: tabs[(index + step + tabs.count) % tabs.count])
    }

    private func handle(_ command: String) {
        guard !modal else { return }
        switch command {
        case "tab": cycleTab(1); return
        case "tabPrev": cycleTab(-1); return
        case "menu": if tab != .settings { switchTab(to: .settings) }; return
        default: break
        }
        switch tab {
        case .home: move(command, index: $homeIndex, columns: nil)
        case .library: move(command, index: $libraryIndex, columns: libraryColumns)
        case .steam: if command == "back" { switchTab(to: .home) }
        case .settings: break   // ConsoleSettingsPage takes its own commands
        }
    }

    /// Home's carousel (one row) and Library's grid (`columns` per row).
    private func move(_ command: String, index: Binding<Int>, columns: Int?) {
        let last = games.count   // the Add game tile
        var next = index.wrappedValue
        switch command {
        case "left": next -= 1
        case "right": next += 1
        case "up": if let columns { next -= columns } else { return }
        case "down": if let columns { next += columns } else { return }
        case "accept": launch(at: index.wrappedValue); return
        case "x": details(at: index.wrappedValue); return
        case "add": browser = true; return
        case "back": if tab != .home { switchTab(to: .home) }; return
        default: return
        }
        next = min(max(next, 0), last)
        guard next != index.wrappedValue else { return }
        withAnimation(Self.motion) { index.wrappedValue = next }
    }
}

// MARK: - Home

struct ConsoleHomeTab: View {
    let games: [LibraryEntry]
    let index: Int
    let accent: Color
    let tap: (Int) -> Void
    let play: () -> Void
    let details: () -> Void
    let add: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(170, max(96, geo.size.height * 0.26))
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 8)
                hero.padding(.horizontal, 36)
                Spacer(minLength: 8)
                carousel(cardWidth: cardWidth)
            }
        }
    }

    @ViewBuilder private var hero: some View {
        if games.indices.contains(index) {
            let entry = games[index]
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.desktop == true ? "WINDOWS DESKTOP" : entry.steamAppID != nil ? "STEAM" : "PC GAME")
                    .font(.system(size: 12, weight: .heavy)).tracking(2).foregroundStyle(accent)
                Text(entry.title)
                    .font(.system(size: 38, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                HStack(spacing: 10) {
                    LibraryBadges(entry: entry).foregroundStyle(.white.opacity(0.75)).fixedSize()
                    if let played = entry.lastPlayed {
                        Text("Played \(played.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
                HStack(spacing: 12) {
                    ConsolePillButton(glyph: "A", title: "Play", icon: "play.fill", primary: true, accent: accent, action: play)
                    ConsolePillButton(glyph: "X", title: "Details", icon: "info.circle", primary: false, accent: accent, action: details)
                }.padding(.top, 6)
            }
            .id(ConsoleHomeView.key(entry))
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("ADD A GAME").font(.system(size: 12, weight: .heavy)).tracking(2).foregroundStyle(accent)
                Text("Bring a Windows game").font(.system(size: 38, weight: .heavy))
                Text("Copy its folder into Madeira › wine › drive_c with the Files app, then choose its .exe.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                ConsolePillButton(glyph: "A", title: "Add game", icon: "plus", primary: true, accent: accent, action: add).padding(.top, 6)
            }
        }
    }

    private func carousel(cardWidth: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 22) {
                    ForEach(Array(0...games.count), id: \.self) { i in
                        ConsoleGameCard(entry: games.indices.contains(i) ? games[i] : nil, focused: i == index,
                                        accent: accent, width: cardWidth)
                            .onTapGesture { tap(i) }
                            .id(i)
                    }
                }
                .padding(.horizontal, 36).padding(.vertical, 18)
            }
            .onChange(of: index) { _, i in
                withAnimation(ConsoleHomeView.motion) { reader.scrollTo(i, anchor: .center) }
            }
            .onAppear { reader.scrollTo(index, anchor: .center) }
        }
        .frame(height: cardWidth * 1.5 + 70)
    }
}

// MARK: - Library

struct ConsoleLibraryGrid: View {
    let games: [LibraryEntry]
    let index: Int
    let accent: Color
    @Binding var columns: Int
    let tap: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let cardWidth: CGFloat = geo.size.width > 700 ? 140 : 100
            let spacing: CGFloat = 22
            let count = max(2, Int((geo.size.width - 48 + spacing) / (cardWidth + spacing)))
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: count), spacing: 24) {
                        ForEach(Array(0...games.count), id: \.self) { i in
                            ConsoleGameCard(entry: games.indices.contains(i) ? games[i] : nil, focused: i == index,
                                            accent: accent, width: cardWidth)
                                .onTapGesture { tap(i) }
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                }
                .onChange(of: index) { _, i in
                    withAnimation(ConsoleHomeView.motion) { reader.scrollTo(i, anchor: .center) }
                }
            }
            .onAppear { columns = count }
            .onChange(of: count) { _, value in columns = value }
        }
    }
}

/// A game's cover (or the Add game tile); the focused one is lifted and outlined.
struct ConsoleGameCard: View {
    let entry: LibraryEntry?
    let focused: Bool
    let accent: Color
    let width: CGFloat
    @ObservedObject private var model = LibraryModel.shared

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                if let entry { LibraryArtwork(entry: entry) } else { addTile }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused ? accent : Color.white.opacity(0.08), lineWidth: focused ? 3 : 1))
            .shadow(color: focused ? accent.opacity(0.55) : .black.opacity(0.45), radius: focused ? 18 : 8, y: focused ? 0 : 4)
            .scaleEffect(focused ? 1.08 : 1)
            Text(entry?.title ?? "Add game")
                .font(.system(size: 13, weight: focused ? .bold : .semibold)).lineLimit(1)
                .foregroundStyle(focused ? Color.white : Color.white.opacity(0.6))
                .frame(width: width)
                .offset(y: focused ? 6 : 0)
        }
        .animation(ConsoleHomeView.motion, value: focused)
        .contentShape(Rectangle())
        .task(id: entry?.id, priority: .utility) {
            if let id = entry?.id, model.entries.contains(where: { $0.id == id }) { await model.refreshMetadata(id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var addTile: some View {
        ZStack {
            Color.white.opacity(0.06)
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 30, weight: .bold))
                Text("Add game").font(.system(size: 13, weight: .semibold))
            }.foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Chrome

struct ConsoleBackdrop: View {
    let entry: LibraryEntry?
    let accent: Color
    var body: some View {
        ZStack {
            ConsoleHome.background
            if let entry, entry.coverFile != nil || entry.steamID != nil || entry.steamAppID != nil {
                LibraryArtwork(entry: entry, backdrop: true)
                    .blur(radius: 36).opacity(0.5).scaleEffect(1.15)
                    .id(ConsoleHomeView.key(entry))
                    .transition(.opacity)
            }
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 760)
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.35), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.35), value: entry.map { ConsoleHomeView.key($0) })
        .ignoresSafeArea()
    }
}

struct ConsoleTopBar: View {
    let tabs: [ConsoleTab]
    let tab: ConsoleTab
    let accent: Color
    let select: (ConsoleTab) -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(accent)
                Text("MADEIRA").font(.system(size: 16, weight: .black)).tracking(3)
            }.fixedSize()
            Spacer(minLength: 6)
            ViewThatFits(in: .horizontal) {
                tabRow(labels: true)
                tabRow(labels: false)
            }
            Spacer(minLength: 6)
            ConsoleStatusCluster(accent: accent).fixedSize()
        }
        .frame(height: 48)
    }

    private func tabRow(labels: Bool) -> some View {
        HStack(spacing: 6) {
            ConsoleGlyph(text: "LB")
            ForEach(tabs) { t in
                Button { select(t) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.icon).font(.system(size: 13, weight: .bold))
                        if labels { Text(t.title).font(.system(size: 14, weight: .bold)) }
                    }
                    .padding(.horizontal, labels ? 14 : 12).frame(height: 34)
                    .foregroundStyle(t == tab ? Color.black : Color.white.opacity(0.75))
                    .background(Capsule().fill(t == tab ? accent : Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
            }
            ConsoleGlyph(text: "RB")
        }
        .fixedSize()
        .animation(ConsoleHomeView.motion, value: tab)
    }
}

/// JIT, controller, battery and time, as a console's status corner.
struct ConsoleStatusCluster: View {
    let accent: Color
    @ObservedObject private var jitState = LibraryJITState.shared
    @State private var pad: String?
    @State private var battery: Float = -1

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill").foregroundStyle(jitState.enabled ? accent : Color.white.opacity(0.3))
                .accessibilityLabel(jitState.enabled ? "JIT enabled" : "JIT not enabled")
            Image(systemName: "gamecontroller.fill").foregroundStyle(pad != nil ? Color.white : Color.white.opacity(0.3))
                .accessibilityLabel(pad ?? "No controller")
            if battery >= 0 {
                Image(systemName: battery > 0.75 ? "battery.100" : battery > 0.5 ? "battery.75" : battery > 0.25 ? "battery.50" : "battery.25")
                    .foregroundStyle(battery <= 0.2 ? Color.red : Color.white.opacity(0.85))
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .onChange(of: context.date) { _, _ in battery = UIDevice.current.batteryLevel }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            battery = UIDevice.current.batteryLevel
            pad = GCController.controllers().first.map { $0.vendorName ?? "Controller" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            pad = GCController.controllers().first.map { $0.vendorName ?? "Controller" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            pad = GCController.controllers().first.map { $0.vendorName ?? "Controller" }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            battery = UIDevice.current.batteryLevel
        }
    }
}

struct ConsoleHint: Identifiable {
    let glyph: String
    let label: String
    var id: String { glyph + label }
    init(_ glyph: String, _ label: String) { self.glyph = glyph; self.label = label }
}

struct ConsoleHintBar: View {
    let hints: [ConsoleHint]
    var body: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            ForEach(hints) { hint in
                HStack(spacing: 6) {
                    ForEach(hint.glyph.split(separator: " ").map(String.init), id: \.self) { ConsoleGlyph(text: $0) }
                    Text(hint.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                }.fixedSize()
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

/// A controller button: face buttons in their usual colours, the others as a key cap.
struct ConsoleGlyph: View {
    let text: String
    private var color: Color? {
        switch text {
        case "A": return Color(red: 0.36, green: 0.80, blue: 0.30)
        case "B": return Color(red: 0.92, green: 0.30, blue: 0.28)
        case "X": return Color(red: 0.25, green: 0.55, blue: 0.95)
        case "Y": return Color(red: 0.98, green: 0.78, blue: 0.20)
        default: return nil
        }
    }
    var body: some View {
        if let color {
            Text(text).font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(color))
        } else {
            Text(text).font(.system(size: 10, weight: .black)).foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.45), lineWidth: 1.2))
        }
    }
}

struct ConsolePillButton: View {
    let glyph: String
    let title: String
    let icon: String
    let primary: Bool
    let accent: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(title).font(.system(size: 16, weight: .bold))
                ConsoleGlyph(text: glyph)
            }
            .padding(.leading, 18).padding(.trailing, 10).frame(height: 44)
            .foregroundStyle(primary ? Color.black : Color.white)
            .background(Capsule().fill(primary ? accent : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

enum ConsoleSettingsCategory: String, CaseIterable, Identifiable {
    case controller, pointer, interface, system, steam, storage, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .controller: return "Controller"
        case .pointer: return "Touch & Mouse"
        case .interface: return "Interface"
        case .system: return "System & JIT"
        case .steam: return "Steam"
        case .storage: return "Games & Saves"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .controller: return "gamecontroller.fill"
        case .pointer: return "cursorarrow.motionlines"
        case .interface: return "paintpalette.fill"
        case .system: return "bolt.fill"
        case .steam: return "cloud.fill"
        case .storage: return "externaldrive.fill"
        case .about: return "info.circle.fill"
        }
    }
}

/// One option on the console Settings page.
struct ConsoleSettingRow: Identifiable {
    enum Kind {
        case toggle(Binding<Bool>)
        case choice([String], Binding<Int>)
        case slider(Binding<Double>, ClosedRange<Double>, step: Double, format: String)
        case action(String?, () -> Void)
        case info(String)
    }
    let id: String
    let icon: String
    let title: String
    var detail: String? = nil
    let kind: Kind
}

/// The library's sheets that the console Settings page opens.
enum ConsoleSettingsSheet: String, Identifiable {
    case jit, display, memory, allSettings, steam, steamSignIn, dock, mono, saves, credits
    var id: String { rawValue }
    var title: String {
        switch self {
        case .jit: return "JIT"
        case .display: return "Display"
        case .memory: return "Memory & Sync"
        case .allSettings: return "All Settings"
        case .steam: return "Steam"
        case .steamSignIn: return "Steam"
        case .dock: return "Madeira Dock"
        case .mono: return ".NET"
        case .saves: return "Saves"
        case .credits: return "Credits"
        }
    }
}

struct ConsoleSettingsPage: View {
    let active: Bool
    @Binding var modal: Bool
    @Binding var column: Int
    let accent: Color
    let enableJIT: () -> Void
    let startDock: (DockGame, Bool) -> Void
    let addGame: () -> Void
    let exit: () -> Void
    @ObservedObject private var input = InputSettings.shared
    @ObservedObject private var jitState = LibraryJITState.shared
    @AppStorage(ConsoleHome.key) private var consoleHome = true
    @AppStorage(ConsoleHome.accentKey) private var accentIndex = 0
    @State private var category = 0
    @State private var row = 0
    @State private var sheet: ConsoleSettingsSheet?
    @State private var developerUI = !FrontendChoice.preferNew
    @State private var restartNotice = false
    @State private var refresh = 0
    @State private var memoryPlus = false
    @State private var pad: String?

    private var categories: [ConsoleSettingsCategory] {
        ConsoleSettingsCategory.allCases.filter { $0 != .steam || SteamSettingsSection.shown }
    }
    private var currentCategory: ConsoleSettingsCategory { categories[min(category, categories.count - 1)] }
    private var rows: [ConsoleSettingRow] { rows(for: currentCategory) }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 640 {
                HStack(alignment: .top, spacing: 22) {
                    categoryList.frame(width: min(250, geo.size.width * 0.3))
                    optionList
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
            } else {
                VStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(Array(categories.enumerated()), id: \.offset) { i, c in categoryChip(i, c) } }
                            .padding(.horizontal, 16)
                    }
                    optionList.padding(.horizontal, 16)
                }
                .padding(.vertical, 10)
            }
        }
        .alert("Restart Madeira", isPresented: $restartNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Close Madeira from the app switcher and open it again to switch interfaces.")
        }
        .sheet(item: $sheet, onDismiss: { refresh += 1 }) { sheet in sheetContent(sheet) }
        .onChange(of: sheet) { _, value in modal = value != nil || restartNotice }
        .onChange(of: restartNotice) { _, value in modal = value || sheet != nil }
        .onAppear {
            memoryPlus = EntitlementStatus.check().increasedMemory
            pad = GCController.controllers().first.map { $0.vendorName ?? "Controller" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            pad = GCController.controllers().first.map { $0.vendorName ?? "Controller" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            pad = GCController.controllers().first.map { $0.vendorName ?? "Controller" }
        }
        .onReceive(LibraryController.shared.commands) { handle($0) }
    }

    // MARK: Layout

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings").font(.system(size: 28, weight: .heavy)).padding(.bottom, 8).padding(.leading, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { i, c in
                        let selected = i == category
                        let focused = selected && column == 0
                        Button { select(category: i) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: c.icon).font(.system(size: 15, weight: .bold)).frame(width: 22)
                                Text(c.title).font(.system(size: 15, weight: .semibold))
                                Spacer(minLength: 0)
                                if selected && column == 1 { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)) }
                            }
                            .padding(.horizontal, 14).frame(height: 46)
                            .foregroundStyle(focused ? Color.black : selected ? accent : Color.white.opacity(0.75))
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(focused ? accent : selected ? accent.opacity(0.14) : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func categoryChip(_ i: Int, _ c: ConsoleSettingsCategory) -> some View {
        Button { select(category: i) } label: {
            Label(c.title, systemImage: c.icon).font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 12).frame(height: 34)
                .foregroundStyle(i == category ? Color.black : Color.white.opacity(0.8))
                .background(Capsule().fill(i == category ? accent : Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(i == category && column == 0 ? Color.white : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }

    private var optionList: some View {
        let rows = self.rows
        return VStack(alignment: .leading, spacing: 10) {
            Text(currentCategory.title.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(2)
                .foregroundStyle(accent).padding(.top, 12).padding(.leading, 4)
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                            ConsoleSettingRowView(row: item, focused: column == 1 && i == row, accent: accent) {
                                withAnimation(ConsoleHomeView.motion) { column = 1; row = i }
                                activate(item)
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 4)
                }
                .onChange(of: row) { _, i in
                    guard rows.indices.contains(i) else { return }
                    withAnimation(ConsoleHomeView.motion) { reader.scrollTo(rows[i].id, anchor: .center) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func select(category i: Int) {
        withAnimation(ConsoleHomeView.motion) { category = i; row = 0; column = 0 }
    }

    // MARK: Options

    private func rows(for category: ConsoleSettingsCategory) -> [ConsoleSettingRow] {
        switch category {
        case .controller:
            var list = [ConsoleSettingRow(id: "pad", icon: "gamecontroller", title: "Controller",
                                          detail: "Navigate Madeira with the D-pad or left stick. In a game, hold View and press Start for the game menu.",
                                          kind: .info(pad ?? "None connected"))]
            if GamepadInput.keyboardMouseAvailable {
                list.append(ConsoleSettingRow(id: "kbm", icon: "keyboard", title: "Controller as keyboard & mouse",
                                              detail: "For games without controller support: the game sees a keyboard and mouse instead of a controller. Applies to every game left on Default in its details; a game can choose its own.",
                                              kind: .toggle($input.padKeyboardMouseDefault)))
                list.append(ConsoleSettingRow(id: "kbm-layout", icon: "list.bullet.rectangle", title: "Keyboard & mouse layout",
                                              detail: "Left stick: W A S D · Right stick: mouse · RT: left click · LT: right click · A: Space · B: Ctrl · X: E · Y: R · LB: Q · RB: F · L3: Shift · R3: C · D-pad: arrow keys · Menu: Esc · View: Tab. Change it per game in Details › Controller binds.",
                                              kind: .info("")))
            } else {
                list.append(ConsoleSettingRow(id: "kbm-off", icon: "keyboard", title: "Controller as keyboard & mouse",
                                              detail: "Turned off in madeira.cfg (MADEIRA_PAD_KBM=0 or MADEIRA_XINPUT=0).", kind: .info("Unavailable")))
            }
            list.append(ConsoleSettingRow(id: "rsmouse", icon: "cursorarrow.rays", title: "Right stick moves the pointer",
                                          detail: "In games that read the controller, the right stick also moves the Windows mouse pointer.",
                                          kind: .toggle($input.padRightStickMouse)))
            return list
        case .pointer:
            let mode = Binding<Int>(get: { input.touchMode ? 2 : input.relative ? 1 : 0 },
                                    set: { input.touchMode = $0 == 2; input.relative = $0 == 1 })
            let sensitivity = Binding<Double>(get: { input.relative ? input.sensRel : input.sensAbs },
                                              set: { if input.relative { input.sensRel = $0 } else { input.sensAbs = $0 } })
            return [
                ConsoleSettingRow(id: "mode", icon: "hand.point.up.left", title: "Pointer mode",
                                  detail: input.touchMode ? "Tap to click where your finger is; hold and move to drag."
                                        : input.relative ? "Drag for relative mouse movement, for mouse-look. Tap to click."
                                        : "Drag the pointer like a trackpad. Tap to click.",
                                  kind: .choice(["Absolute", "Relative", "Touch"], mode)),
                ConsoleSettingRow(id: "touch-sens", icon: "hand.draw", title: "Touch sensitivity",
                                  kind: .slider(sensitivity, 0.1...8, step: 0.1, format: "%.1f")),
                ConsoleSettingRow(id: "mouse-sens", icon: "computermouse", title: "Mouse sensitivity",
                                  detail: "A connected mouse or trackpad.",
                                  kind: .slider($input.sensMouse, 0.25...4, step: 0.05, format: "%.2f")),
                ConsoleSettingRow(id: "assistive", icon: "hand.tap", title: "Ignore AssistiveTouch clicks",
                                  detail: "While a hardware mouse is in use.", kind: .toggle($input.ignoreTouchesWithMouse)),
            ]
        case .interface:
            var list = [
                ConsoleSettingRow(id: "accent", icon: "paintpalette", title: "Accent colour",
                                  kind: .choice(ConsoleHome.accents.map { $0.name }, $accentIndex)),
                ConsoleSettingRow(id: "console", icon: "tv", title: "Console home",
                                  detail: "Off: the touch library with its tab bar. Turn it back on in Settings › Interface there.",
                                  kind: .toggle($consoleHome)),
                ConsoleSettingRow(id: "developer", icon: "hammer", title: "Developer interface",
                                  detail: "Madeira's original diagnostic screen. Applies after Madeira restarts.",
                                  kind: .toggle(Binding(get: { developerUI }, set: { on in
                                      developerUI = on; FrontendChoice.choose(new: !on); restartNotice = true
                                  }))),
            ]
            if MadeiraConfig.flag("MADEIRA_RUNTIME_SETTINGS") {
                list.append(ConsoleSettingRow(id: "display", icon: "display", title: "Display refresh rate", kind: .action(nil, { sheet = .display })))
            }
            return list
        case .system:
            var list = [
                ConsoleSettingRow(id: "jit", icon: "bolt", title: "JIT", detail: "Needed to play. Enable it before starting a game.",
                                  kind: jitState.enabled ? ConsoleSettingRow.Kind.info("Enabled") : ConsoleSettingRow.Kind.action("Enable", enableJIT)),
                ConsoleSettingRow(id: "memory", icon: "memorychip", title: "Memory+", kind: .info(memoryPlus ? "Available" : "Unavailable")),
                ConsoleSettingRow(id: "jit-setup", icon: "wrench.and.screwdriver", title: "JIT setup",
                                  detail: "JIT method, StikDebug, pairing and LocalDevVPN.", kind: .action(nil, { sheet = .jit })),
                ConsoleSettingRow(id: "logging", icon: "doc.text.magnifyingglass", title: "Extended logging",
                                  detail: "Heavy diagnostics. Leave off unless a run needs explaining.", kind: .toggle($input.diagnostics)),
            ]
            if MadeiraConfig.flag("MADEIRA_RUNTIME_SETTINGS") {
                list.append(ConsoleSettingRow(id: "memsync", icon: "cpu", title: "Memory & sync",
                                              detail: "JIT pool, video memory, swap and the sync engine.", kind: .action(nil, { sheet = .memory })))
            }
            list.append(ConsoleSettingRow(id: "all", icon: "slider.horizontal.3", title: "All settings",
                                          detail: "Every madeira.cfg option.", kind: .action(nil, { sheet = .allSettings })))
            return list
        case .steam:
            var list = [ConsoleSettingRow(id: "steam", icon: "person.crop.circle", title: "Steam account",
                                          detail: "Sign-in, Madeira Dock and Steam setup.", kind: .action(nil, { sheet = .steam }))]
            if MadeiraDock.enabled {
                list.append(ConsoleSettingRow(id: "dock", icon: "shippingbox", title: "Madeira Dock", kind: .action(nil, { sheet = .dock })))
            }
            return list
        case .storage:
            return [
                ConsoleSettingRow(id: "add", icon: "plus.square", title: "Add a game",
                                  detail: "Choose a game's .exe in drive_c.", kind: .action(nil, addGame)),
                ConsoleSettingRow(id: "mono", icon: "shippingbox", title: ".NET (Wine Mono)",
                                  detail: "For games and launchers built on .NET.", kind: .action(nil, { sheet = .mono })),
                ConsoleSettingRow(id: "saves", icon: "externaldrive.badge.timemachine", title: "Save backups",
                                  detail: "Back up and restore your saves.", kind: .action(nil, { sheet = .saves })),
            ]
        case .about:
            return [
                ConsoleSettingRow(id: "version", icon: "number", title: "Version", kind: .info(BuildStamp.text)),
                ConsoleSettingRow(id: "credits", icon: "heart", title: "Credits", kind: .action(nil, { sheet = .credits })),
            ]
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: ConsoleSettingsSheet) -> some View {
        switch sheet {
        case .allSettings: AllSettingsView()
        case .steamSignIn: SteamSignInView()
        case .dock: MadeiraDockView(start: startDock)
        default:
            NavigationStack {
                Form { formContent(sheet) }
                    .navigationTitle(sheet.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.sheet = nil } } }
            }
        }
    }

    @ViewBuilder private func formContent(_ sheet: ConsoleSettingsSheet) -> some View {
        switch sheet {
        case .jit: JITSettingsSection()
        case .display: DisplayRateSettings()
        case .memory: RuntimeMemorySyncSettings(open: { open($0) }, refresh: refresh)
        case .steam: SteamSettingsSection(open: { open($0) })
        case .mono: WineMonoSettingsSection()
        case .saves: SavesSection()
        case .credits: MadeiraCreditsSection()
        case .allSettings, .steamSignIn, .dock: EmptyView()
        }
    }

    /// A Settings sheet asked for another (All settings, Steam sign-in, Dock): close it, then open that one.
    private func open(_ next: SettingsSheet) {
        let target: ConsoleSettingsSheet
        switch next {
        case .allSettings: target = .allSettings
        case .steamSignIn: target = .steamSignIn
        case .dock: target = .dock
        }
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet = target }
    }

    // MARK: Controller

    private func activate(_ item: ConsoleSettingRow) {
        switch item.kind {
        case .toggle(let value): value.wrappedValue.toggle()
        case .choice(let options, let value): value.wrappedValue = (value.wrappedValue + 1) % max(options.count, 1)
        case .action(_, let action): action()
        case .slider, .info: break
        }
    }

    /// Left/right on a choice or a slider; false when the option has nothing to adjust.
    private func adjust(_ item: ConsoleSettingRow, by step: Int) -> Bool {
        switch item.kind {
        case .choice(let options, let value):
            value.wrappedValue = (value.wrappedValue + step + options.count) % max(options.count, 1); return true
        case .slider(let value, let range, let size, _):
            value.wrappedValue = min(max(value.wrappedValue + Double(step) * size, range.lowerBound), range.upperBound); return true
        default: return false
        }
    }

    private func handle(_ command: String) {
        guard active else { return }
        if sheet != nil { if command == "back" { sheet = nil }; return }
        if restartNotice { return }
        let rows = self.rows
        withAnimation(ConsoleHomeView.motion) {
            switch command {
            case "up":
                if column == 0 { if category > 0 { category -= 1; row = 0 } } else { row = max(0, row - 1) }
            case "down":
                if column == 0 { if category < categories.count - 1 { category += 1; row = 0 } } else { row = min(rows.count - 1, row + 1) }
            case "right":
                if column == 0 { if !rows.isEmpty { column = 1; row = min(row, rows.count - 1) } }
                else if rows.indices.contains(row) { _ = adjust(rows[row], by: 1) }
            case "left":
                if column == 1, rows.indices.contains(row), !adjust(rows[row], by: -1) { column = 0 }
            case "accept":
                if column == 0 { if !rows.isEmpty { column = 1; row = 0 } }
                else if rows.indices.contains(row) { activate(rows[row]) }
            case "back":
                if column == 1 { column = 0 } else { exit() }
            default: break
            }
        }
    }
}

struct ConsoleSettingRowView: View {
    let row: ConsoleSettingRow
    let focused: Bool
    let accent: Color
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(focused ? Color.black : accent)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(focused ? accent : accent.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 16, weight: .semibold))
                if let detail = row.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(focused ? 0.13 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(focused ? accent : Color.clear, lineWidth: 2))
        .scaleEffect(focused ? 1.01 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: tap)
    }

    @ViewBuilder private var trailing: some View {
        switch row.kind {
        case .toggle(let value):
            // The row's tap toggles; the switch only shows the state.
            Toggle("", isOn: value).labelsHidden().tint(accent).allowsHitTesting(false)
        case .choice(let options, let value):
            HStack(spacing: 10) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).opacity(focused ? 1 : 0.35)
                Text(options.indices.contains(value.wrappedValue) ? options[value.wrappedValue] : "")
                    .font(.system(size: 15, weight: .semibold)).frame(minWidth: 70)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).opacity(focused ? 1 : 0.35)
            }.foregroundStyle(focused ? accent : Color.white.opacity(0.8))
        case .slider(let value, let range, _, let format):
            HStack(spacing: 10) {
                Slider(value: value, in: range).frame(width: 150).tint(accent)
                Text(String(format: format, value.wrappedValue)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        case .action(let label, _):
            HStack(spacing: 8) {
                if let label { Text(label).font(.system(size: 14, weight: .bold)).foregroundStyle(accent) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            }
        case .info(let value):
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
    }
}
