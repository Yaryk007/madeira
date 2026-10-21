import SwiftUI
import Combine
import GameController
import Network
import UIKit

/// GamehubiOS: the home in the layout of GameSir's GameHub (landscape). A top
/// bar of icon tabs — Library, Community, Home, Ranking, Profile — where the
/// selected tab shows its name, and a status corner (notifications, controller,
/// time, Wi-Fi, battery). Library opens on four tiles: My Games, Steam, Epic
/// and Import. Home is the console home's hero and carousel, Ranking lists
/// Steam's most played games, Profile holds the account and the console
/// Settings. LB/RB change tabs and the D-pad moves, as in ConsoleHome.swift,
/// whose cards, settings page and glyphs this reuses.
enum GameHub {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let tile = Color(red: 0.145, green: 0.145, blue: 0.157)
    static let tileStroke = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.5)
    static let link = Color(red: 0.23, green: 0.62, blue: 1.0)
    static let postBlue = LinearGradient(colors: [Color(red: 0.12, green: 0.62, blue: 0.93), Color(red: 0.05, green: 0.47, blue: 0.82)],
                                         startPoint: .top, endPoint: .bottom)
    /// The accent of focus rings and selections.
    static let accent = Color.white
}

enum GameHubTab: Int, CaseIterable, Identifiable {
    case library, community, home, ranking, profile
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .library: return "Library"
        case .community: return "Community"
        case .home: return "Home"
        case .ranking: return "Ranking"
        case .profile: return "Profile"
        }
    }
    func icon(selected: Bool) -> String {
        switch self {
        case .library: return selected ? "square.grid.2x2.fill" : "square.grid.2x2"
        case .community: return selected ? "text.bubble.fill" : "text.bubble"
        case .home: return selected ? "house.fill" : "house"
        case .ranking: return selected ? "chart.bar.fill" : "chart.bar"
        case .profile: return selected ? "face.smiling.inverse" : "face.smiling"
        }
    }
}

/// Library's four tiles and the pages behind them.
enum GameHubShelf: Int, CaseIterable, Identifiable {
    case myGames, steam, epic, importGame
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .myGames: return "My Games"
        case .steam: return "Steam"
        case .epic: return "Epic"
        case .importGame: return "Import"
        }
    }
}

struct GameHubHomeView: View {
    var play: (LibraryEntry) -> Void
    var enableJIT: () -> Void
    var startDock: (DockGame, Bool) -> Void = { _, _ in }
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var steamGames = SteamGamesModel.shared
    @ObservedObject private var onboarding = OnboardingModel.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ConsoleHome.accentKey) private var accentIndex = 0
    @State private var tab: GameHubTab = .library
    /// The Library page behind a tile; nil shows the tiles.
    @State private var shelf: GameHubShelf?
    @State private var tileIndex = 0
    /// Every game (Home), and the games that are not Steam's (My Games).
    @State private var games: [LibraryEntry] = []
    @State private var homeIndex = 0
    @State private var myGamesIndex = 0
    @State private var myGamesColumns = 4
    @State private var selected: LibraryEntry?
    @State private var browser = false
    @State private var settingsModal = false
    @State private var settingsColumn = 0
    @State private var notifications = false

    private var accent: Color { ConsoleHome.accent(accentIndex) }
    private var modal: Bool { selected != nil || browser || onboarding.presented || settingsModal || notifications || model.error != nil }
    private var jitProblem: JITCoordinator.ConnectionProblem? {
        jit.connectionProblem.flatMap { model.error == $0.message ? $0 : nil }
    }
    private var myGames: [LibraryEntry] { games.filter { $0.steamAppID == nil } }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                GameHubTopBar(tab: tab, select: { switchTab(to: $0) },
                              search: tab == .community ? { CommunityModel.shared.searching.toggle() } : nil,
                              layoutSwitch: { UserDefaults.standard.set(false, forKey: ConsoleHome.key) },
                              notifications: { notifications = true },
                              controller: { switchTab(to: .profile) })
                    .padding(.horizontal, 34).padding(.top, 8)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .tint(accent)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .alert(jitProblem == nil ? "Library" : "Couldn't Enable JIT",
               isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            if let jitProblem { jitConnectionActions(jitProblem, retry: enableJIT) { model.error = nil } }
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Notifications", isPresented: $notifications) {
            Button("OK", role: .cancel) {}
        } message: { Text("You're all caught up.") }
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
            LogStore.shared.log("[gamehub-home] shown games=\(games.count)")
        }
    }

    @ViewBuilder private var backdrop: some View {
        ZStack {
            GameHub.background
            if tab == .community || tab == .ranking {
                LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .center)
            }
            if tab == .home, games.indices.contains(homeIndex) {
                ConsoleBackdrop(entry: games[homeIndex], accent: accent)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .library:
            libraryContent.transition(.opacity)
        case .community:
            GameHubCommunityPage().transition(.opacity)
        case .home:
            ConsoleHomeTab(games: games, index: homeIndex, accent: accent,
                           tap: { tapped($0, focus: $homeIndex, in: games) },
                           play: { launch(games, at: homeIndex) }, details: { details(games, at: homeIndex) },
                           add: { browser = true })
                .transition(.opacity)
        case .ranking:
            GameHubRankingPage(open: openSteamApp).transition(.opacity)
        case .profile:
            GameHubProfilePage(active: tab == .profile && !modal, modal: $settingsModal, column: $settingsColumn,
                               accent: accent, games: games.count, enableJIT: enableJIT, startDock: startDock,
                               addGame: { browser = true }, exit: { switchTab(to: .library) })
                .transition(.opacity)
        }
    }

    @ViewBuilder private var libraryContent: some View {
        switch shelf {
        case nil:
            GameHubShelves(focus: tileIndex, tap: { i in
                if tileIndex == i { openShelf(GameHubShelf.allCases[i]) }
                else { tileIndex = i; openShelf(GameHubShelf.allCases[i]) }
            })
        case .myGames?:
            GameHubShelfPage(title: "My Games", back: closeShelf) {
                ConsoleLibraryGrid(games: myGames, index: myGamesIndex, accent: accent, columns: $myGamesColumns,
                                   tap: { tapped($0, focus: $myGamesIndex, in: myGames) })
            }
        case .steam?:
            GameHubShelfPage(title: "Steam", back: closeShelf) {
                GeometryReader { geo in
                    ScrollView {
                        SteamGamesSection(search: "", layout: "cards", sort: "played", width: geo.size.width - 68,
                                          part: .all, open: { selected = $0 })
                            .padding(.horizontal, 34).padding(.vertical, 12)
                    }
                    .refreshable { await SteamGamesSection.refresh() }
                }
            }
        case .epic?:
            GameHubShelfPage(title: "Epic", back: closeShelf) {
                GameHubEmptyState(icon: "e.square", title: "Epic Games Store",
                                  message: "Signing in to Epic is not supported yet. Games you installed elsewhere can be added from Import or My Games.",
                                  action: ("Import a game", { browser = true }))
            }
        case .importGame?:
            EmptyView()
        }
    }

    // MARK: Navigation

    private func switchTab(to newTab: GameHubTab) {
        guard newTab != tab else { if newTab == .library { closeShelf() }; return }
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.18)) { tab = newTab }
        if newTab == .profile { settingsColumn = 0 }
    }

    private func cycleTab(_ step: Int) {
        let all = GameHubTab.allCases
        let index = all.firstIndex(of: tab) ?? 0
        switchTab(to: all[(index + step + all.count) % all.count])
    }

    private func openShelf(_ target: GameHubShelf) {
        if target == .importGame { browser = true; return }
        withAnimation(ConsoleHomeView.motion) { shelf = target }
    }

    private func closeShelf() {
        withAnimation(ConsoleHomeView.motion) { shelf = nil }
    }

    /// A Steam app from the charts: its library entry when it is installed, else its store page.
    private func openSteamApp(_ appID: Int) {
        if let entry = games.first(where: { $0.steamAppID == appID }) { selected = entry; return }
        if let url = URL(string: "https://store.steampowered.com/app/\(appID)") { UIApplication.shared.open(url) }
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
        list.sort { a, b in
            if a.lastPlayed != b.lastPlayed { return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast) }
            if (a.desktop == true) != (b.desktop == true) { return b.desktop == true }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        let homeID = games.indices.contains(homeIndex) ? ConsoleHomeView.key(games[homeIndex]) : nil
        games = list
        homeIndex = homeID.flatMap { id in list.firstIndex { ConsoleHomeView.key($0) == id } } ?? min(homeIndex, list.count)
        myGamesIndex = min(myGamesIndex, myGames.count)
    }

    /// Plays a game that is not Steam's; a Steam game opens its details page, which
    /// checks its download and sign-in first. The last index is the Add game tile.
    private func launch(_ list: [LibraryEntry], at index: Int) {
        guard list.indices.contains(index) else { browser = true; return }
        let entry = list[index]
        if entry.steamAppID != nil { selected = entry; return }
        LogStore.shared.log("[gamehub-home] play \(entry.title)")
        model.save(entry); play(entry)
    }

    private func details(_ list: [LibraryEntry], at index: Int) {
        guard list.indices.contains(index) else { browser = true; return }
        selected = list[index]
    }

    private func tapped(_ index: Int, focus: Binding<Int>, in list: [LibraryEntry]) {
        if focus.wrappedValue == index { launch(list, at: index) }
        else { withAnimation(ConsoleHomeView.motion) { focus.wrappedValue = index } }
    }

    // MARK: Controller

    private func handle(_ command: String) {
        guard !modal else { return }
        switch command {
        case "tab": cycleTab(1); return
        case "tabPrev": cycleTab(-1); return
        case "menu": switchTab(to: .profile); return
        default: break
        }
        switch tab {
        case .library:
            switch shelf {
            case nil:
                switch command {
                case "left": tileIndex = max(0, tileIndex - 1)
                case "right": tileIndex = min(GameHubShelf.allCases.count - 1, tileIndex + 1)
                case "accept": openShelf(GameHubShelf.allCases[tileIndex])
                case "add": browser = true
                default: break
                }
            case .myGames?:
                if command == "back" { closeShelf() } else { move(command, index: $myGamesIndex, in: myGames, columns: myGamesColumns) }
            default:
                if command == "back" { closeShelf() }
            }
        case .home: move(command, index: $homeIndex, in: games, columns: nil)
        case .community, .ranking: if command == "back" { switchTab(to: .library) }
        case .profile: break   // ConsoleSettingsPage takes its own commands
        }
    }

    private func move(_ command: String, index: Binding<Int>, in list: [LibraryEntry], columns: Int?) {
        var next = index.wrappedValue
        switch command {
        case "left": next -= 1
        case "right": next += 1
        case "up": if let columns { next -= columns } else { return }
        case "down": if let columns { next += columns } else { return }
        case "accept": launch(list, at: index.wrappedValue); return
        case "x": details(list, at: index.wrappedValue); return
        case "add": browser = true; return
        case "back": if tab == .home { switchTab(to: .library) }; return
        default: return
        }
        next = min(max(next, 0), list.count)
        guard next != index.wrappedValue else { return }
        withAnimation(ConsoleHomeView.motion) { index.wrappedValue = next }
    }
}

// MARK: - Top bar

struct GameHubTopBar: View {
    let tab: GameHubTab
    let select: (GameHubTab) -> Void
    /// Community's search; nil hides the glass.
    var search: (() -> Void)?
    let layoutSwitch: () -> Void
    let notifications: () -> Void
    let controller: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 34) {
                ForEach(GameHubTab.allCases) { t in
                    Button { select(t) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: t.icon(selected: t == tab)).font(.system(size: 21, weight: .medium))
                            if t == tab { Text(t.title).font(.system(size: 20, weight: .medium)).fixedSize() }
                        }
                        .foregroundStyle(t == tab ? Color.white : Color.white.opacity(0.88))
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.title)
                    .accessibilityAddTraits(t == tab ? .isSelected : [])
                }
            }
            .animation(ConsoleHomeView.motion, value: tab)
            Spacer(minLength: 16)
            HStack(spacing: 30) {
                if let search {
                    Button(action: search) { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search")
                }
                Button(action: layoutSwitch) { GameHubLayoutSwitchIcon().frame(width: 22, height: 22) }
                    .accessibilityLabel("Switch to the classic library")
                Button(action: notifications) { Image(systemName: "bell") }.accessibilityLabel("Notifications")
                Button(action: controller) { Image(systemName: "gamecontroller") }.accessibilityLabel("Controller")
            }
            .buttonStyle(.plain)
            .font(.system(size: 20, weight: .regular))
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 14)
            GameHubStatus()
        }
        .frame(height: 56)
    }
}

/// GameHub's layout switch: a phone upright beside a turned one.
struct GameHubLayoutSwitchIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.12).stroke(lineWidth: w * 0.08)
                    .frame(width: w * 0.5, height: h * 0.9).offset(x: w * 0.04, y: h * 0.05)
                Circle().frame(width: w * 0.1).offset(x: w * 0.16, y: h * 0.62)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.66, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.12))
                    p.addQuadCurve(to: CGPoint(x: w * 0.94, y: h * 0.24), control: CGPoint(x: w * 0.94, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.76))
                    p.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.88), control: CGPoint(x: w * 0.94, y: h * 0.88))
                    p.addLine(to: CGPoint(x: w * 0.66, y: h * 0.88))
                    p.move(to: CGPoint(x: w * 0.66, y: h * 0.5))
                    p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.5))
                }
                .stroke(style: StrokeStyle(lineWidth: w * 0.08, lineCap: .round))
            }
        }
    }
}

/// Time, Wi-Fi and battery, as GameHub draws them.
struct GameHubStatus: View {
    @State private var battery: Float = -1
    @StateObject private var network = GameHubNetworkState()

    var body: some View {
        HStack(spacing: 12) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .monospacedDigit()
                    .onChange(of: context.date) { _, _ in battery = UIDevice.current.batteryLevel }
            }
            Image(systemName: network.wifi ? "wifi" : network.online ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                .font(.system(size: 17, weight: .semibold))
            if battery >= 0 {
                HStack(spacing: 4) {
                    Image(systemName: battery > 0.9 ? "battery.100percent" : battery > 0.6 ? "battery.75percent"
                          : battery > 0.35 ? "battery.50percent" : battery > 0.15 ? "battery.25percent" : "battery.0percent")
                        .font(.system(size: 20))
                        .foregroundStyle(battery <= 0.15 ? Color.red : Color.white)
                    Text("\(Int((battery * 100).rounded()))%").monospacedDigit()
                }
            }
        }
        .font(.system(size: 18, weight: .regular))
        .fixedSize()
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            battery = UIDevice.current.batteryLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            battery = UIDevice.current.batteryLevel
        }
    }
}

final class GameHubNetworkState: ObservableObject {
    @Published var wifi = true
    @Published var online = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.online = path.status == .satisfied
                self?.wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: DispatchQueue(label: "gamehub.network"))
    }

    deinit { monitor.cancel() }
}

// MARK: - Library

struct GameHubShelves: View {
    let focus: Int
    let tap: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            let width = (geo.size.width - 68 - spacing * 3) / 4
            VStack {
                HStack(spacing: spacing) {
                    ForEach(GameHubShelf.allCases) { shelf in
                        Button { tap(shelf.rawValue) } label: {
                            VStack(spacing: 10) {
                                GameHubShelfIcon(shelf: shelf).frame(width: 34, height: 34)
                                Text(shelf.title).font(.system(size: 17, weight: .regular))
                            }
                            .frame(width: width, height: min(104, max(84, width * 0.48)))
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GameHub.tile))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(focus == shelf.rawValue && GCController.current != nil ? Color.white.opacity(0.85) : GameHub.tileStroke,
                                        lineWidth: focus == shelf.rawValue && GCController.current != nil ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(shelf.title)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 34).padding(.top, 14)
        }
    }
}

struct GameHubShelfIcon: View {
    let shelf: GameHubShelf
    var body: some View {
        switch shelf {
        case .myGames:
            // Four soft squares, as GameHub's "My Games".
            let gradient = LinearGradient(colors: [.white, Color(white: 0.72)], startPoint: .top, endPoint: .bottom)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow { RoundedRectangle(cornerRadius: 4).fill(gradient); Circle().fill(gradient) }
                GridRow { RoundedRectangle(cornerRadius: 4).fill(gradient); RoundedRectangle(cornerRadius: 4).fill(gradient) }
            }
        case .steam:
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.07, green: 0.16, blue: 0.33), Color(red: 0.0, green: 0.42, blue: 0.75)],
                                             startPoint: .top, endPoint: .bottom))
                Image(systemName: "gearshape.2.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
        case .epic:
            ZStack {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 0, bottomTrailing: 0, topTrailing: 3))
                    .fill(Color(white: 0.2))
                    .overlay(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 0, bottomTrailing: 0, topTrailing: 3))
                        .stroke(Color(white: 0.4), lineWidth: 0.6))
                VStack(spacing: 0) {
                    Text("EPIC").font(.system(size: 10, weight: .black)).tracking(-0.3)
                    Text("GAMES").font(.system(size: 4.5, weight: .heavy))
                }.foregroundStyle(.white).offset(y: -2)
            }
            .frame(width: 27, height: 32)
        case .importGame:
            Image(systemName: "plus").font(.system(size: 32, weight: .thin))
        }
    }
}

/// A Library page behind a tile: a back row and its content.
struct GameHubShelfPage<Content: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    Text(title).font(.system(size: 22, weight: .semibold))
                    ConsoleGlyph(text: "B").padding(.leading, 4)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 34).padding(.top, 6)
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct GameHubEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38, weight: .light)).foregroundStyle(GameHub.secondary)
            Text(title).font(.system(size: 19, weight: .semibold))
            Text(message).font(.system(size: 14)).foregroundStyle(GameHub.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 440)
            if let action {
                Button(action: action.1) {
                    Text(action.0).font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22).frame(height: 38)
                        .background(Capsule().fill(GameHub.postBlue))
                }
                .buttonStyle(.plain).padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ranking

/// Steam's most played games (ISteamChartsService, no key needed): "Hot" by
/// rank, "Soaring" by the places climbed since last week, and your own most
/// played when signed in.
@MainActor final class GameHubRankingModel: ObservableObject {
    static let shared = GameHubRankingModel()
    struct Rank: Identifiable, Hashable { let appID: Int; let rank: Int; let lastWeek: Int; let peak: Int; var id: Int { appID } }
    @Published private(set) var ranks: [Rank] = []
    @Published private(set) var names: [Int: String] = [:]
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var loaded: Date?

    func load(force: Bool = false) async {
        if !force, let loaded, Date().timeIntervalSince(loaded) < 600, !ranks.isEmpty { return }
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        struct Response: Decodable {
            struct Body: Decodable { let ranks: [Item]? }
            struct Item: Decodable { let rank: Int; let appid: Int; let last_week_rank: Int?; let peak_in_game: Int? }
            let response: Body
        }
        do {
            let url = URL(string: "https://api.steampowered.com/ISteamChartsService/GetMostPlayedGames/v1/")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let items = try JSONDecoder().decode(Response.self, from: data).response.ranks ?? []
            ranks = items.map { Rank(appID: $0.appid, rank: $0.rank, lastWeek: $0.last_week_rank ?? -1, peak: $0.peak_in_game ?? 0) }
            loaded = Date()
            LogStore.shared.log("[gamehub-ranking] \(ranks.count) games")
            await loadNames(ranks.prefix(40).map(\.appID))
        } catch {
            self.error = "Steam's charts could not be loaded. Check the connection and try again."
            LogStore.shared.log("[gamehub-ranking] failed: \(error.localizedDescription)", level: .error)
        }
    }

    /// Store names, a few at a time (appdetails answers one app per request).
    private func loadNames(_ ids: [Int]) async {
        struct Details: Decodable { let success: Bool; let data: Body?; struct Body: Decodable { let name: String } }
        for id in ids where names[id] == nil {
            if let owned = SteamOwnedLibrary.shared.game(id) { names[id] = owned.name; continue }
            guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(id)&filters=basic") else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let decoded = try? JSONDecoder().decode([String: Details].self, from: data),
               let name = decoded[String(id)]?.data?.name {
                names[id] = name
            }
        }
    }
}

struct GameHubRankingPage: View {
    let open: (Int) -> Void
    @ObservedObject private var ranking = GameHubRankingModel.shared
    @ObservedObject private var steam = SteamOwnedLibrary.shared

    private var hot: [GameHubRankingModel.Rank] { Array(ranking.ranks.prefix(20)) }
    private var soaring: [GameHubRankingModel.Rank] {
        Array(ranking.ranks.filter { $0.lastWeek > 0 && $0.lastWeek > $0.rank }
            .sorted { ($0.lastWeek - $0.rank) > ($1.lastWeek - $1.rank) }.prefix(20))
    }
    private var mine: [(Int, String)] {
        steam.playtime.filter { $0.value.minutes > 0 }.sorted { $0.value.minutes > $1.value.minutes }.prefix(20)
            .map { ($0.key, steam.game($0.key)?.name ?? "App \($0.key)") }
    }

    var body: some View {
        Group {
            if ranking.ranks.isEmpty, let error = ranking.error {
                GameHubEmptyState(icon: "chart.bar", title: "Ranking", message: error,
                                  action: ("Try again", { Task { await ranking.load(force: true) } }))
            } else if ranking.ranks.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        column("Hot", subtitle: "Most played on Steam", tint: Color(red: 1, green: 0.42, blue: 0.25)) {
                            ForEach(hot) { row($0.rank, $0.appID, detail: $0.peak > 0 ? "\($0.peak.formatted()) playing at peak" : nil) }
                        }
                        column("Soaring", subtitle: "Climbing this week", tint: Color(red: 0.3, green: 0.85, blue: 0.5)) {
                            ForEach(Array(soaring.enumerated()), id: \.element.id) { i, r in
                                row(i + 1, r.appID, detail: "▲ \(r.lastWeek - r.rank) places")
                            }
                        }
                        if !mine.isEmpty {
                            column("Yours", subtitle: "Your most played", tint: GameHub.link) {
                                ForEach(Array(mine.enumerated()), id: \.element.0) { i, item in
                                    row(i + 1, item.0, name: item.1, detail: steam.playtime[item.0]?.played)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 34).padding(.vertical, 12)
                }
            }
        }
        .task { await ranking.load() }
    }

    private func column<Rows: View>(_ title: String, subtitle: String, tint: Color, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .heavy)).foregroundStyle(tint)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(GameHub.secondary)
            }
            .padding(16)
            ScrollView { LazyVStack(spacing: 2) { rows() }.padding(.horizontal, 8).padding(.bottom, 10) }
        }
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.18), GameHub.tile], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(GameHub.tileStroke))
    }

    private func row(_ place: Int, _ appID: Int, name: String? = nil, detail: String?) -> some View {
        Button { open(appID) } label: {
            HStack(spacing: 12) {
                Text("\(place)").font(.system(size: 17, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(place <= 3 ? Color(red: 1, green: 0.78, blue: 0.3) : GameHub.secondary)
                    .frame(width: 26)
                AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/capsule_184x69.jpg")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.white.opacity(0.06) }
                .frame(width: 92, height: 35).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? ranking.names[appID] ?? "App \(appID)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(GameHub.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile

struct GameHubProfilePage: View {
    let active: Bool
    @Binding var modal: Bool
    @Binding var column: Int
    let accent: Color
    let games: Int
    let enableJIT: () -> Void
    let startDock: (DockGame, Bool) -> Void
    let addGame: () -> Void
    let exit: () -> Void
    @ObservedObject private var signIn = SteamSignInModel.shared
    @ObservedObject private var jitState = LibraryJITState.shared
    @ObservedObject private var community = CommunityModel.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                    Image(systemName: "face.smiling").font(.system(size: 30))
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(community.account?.nickname ?? signIn.accountName ?? "Guest").font(.system(size: 22, weight: .semibold))
                    HStack(spacing: 14) {
                        Label(signIn.accountName == nil ? "Steam: not signed in" : "Steam: \(signIn.accountName!)", systemImage: "person.crop.circle")
                        Label("\(games) games", systemImage: "square.grid.2x2")
                        Label(jitState.enabled ? "JIT on" : "JIT off", systemImage: "bolt.fill")
                            .foregroundStyle(jitState.enabled ? accent : GameHub.secondary)
                    }
                    .font(.system(size: 13)).foregroundStyle(GameHub.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 34).padding(.vertical, 8)
            ConsoleSettingsPage(active: active, modal: $modal, column: $column, accent: accent,
                                enableJIT: enableJIT, startDock: startDock, addGame: addGame, exit: exit)
        }
        .onAppear { signIn.refresh() }
    }
}
