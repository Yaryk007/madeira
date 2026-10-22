import SwiftUI
import Combine
import GameController
import Network
import UIKit

/// GamehubiOS: the home in the layout of GameSir's GameHub (landscape). A top
/// bar of icon tabs — Library, Community, Home, Ranking, Profile — where the
/// selected tab shows its name, and a status corner whose buttons change with
/// the tab. Library shows your games as a row of covers (the focused one large,
/// its art behind the page) over the My Games / Steam / Epic / Import tiles.
/// The other tabs and the full-screen Settings and Download Manager pages are
/// in GameHubPages.swift. LB/RB change tabs and the D-pad moves, as in
/// ConsoleHome.swift, whose cards, settings page and glyphs this reuses.
enum GameHub {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let tile = Color(red: 0.145, green: 0.145, blue: 0.157)
    static let card = Color(red: 0.118, green: 0.118, blue: 0.13)
    static let button = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let tileStroke = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.5)
    static let link = Color(red: 0.23, green: 0.62, blue: 1.0)
    static let warning = Color(red: 1.0, green: 0.55, blue: 0.1)
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

/// The full-screen pages GameHub opens over the tabs.
enum GameHubPage: Identifiable {
    case settings, downloads
    var id: Int { hashValue }
}

/// The status corner's buttons; each tab shows its own, as GameHub does.
enum GameHubAction: Hashable {
    case search, layoutSwitch, notifications, controller, scan, downloads, settings
    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .layoutSwitch: return ""
        case .notifications: return "bell"
        case .controller: return "gamecontroller"
        case .scan: return "viewfinder"
        case .downloads: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
    var label: String {
        switch self {
        case .search: return "Search"
        case .layoutSwitch: return "Switch to the classic library"
        case .notifications: return "Notifications"
        case .controller: return "Controller settings"
        case .scan: return "Sign in to Steam with a QR code"
        case .downloads: return "Download Manager"
        case .settings: return "Settings"
        }
    }
    static func forTab(_ tab: GameHubTab) -> [GameHubAction] {
        switch tab {
        case .library, .ranking: return [.layoutSwitch, .notifications, .controller]
        case .community: return [.search, .layoutSwitch, .notifications, .controller]
        case .home: return [.search, .layoutSwitch, .controller]
        case .profile: return [.scan, .downloads, .settings]
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
    /// The Library page behind a tile; nil shows the covers and tiles.
    @State private var shelf: GameHubShelf?
    /// Library's focus: the covers (0) or the tiles (1), and the index in each.
    @State private var libraryRow = 0
    @State private var coverIndex = 0
    @State private var tileIndex = 0
    /// Every game, last played first (the covers and Home's PC Games).
    @State private var games: [LibraryEntry] = []
    @State private var myGamesIndex = 0
    @State private var myGamesColumns = 4
    @State private var homeSection = 0
    @State private var selected: LibraryEntry?
    @State private var browser = false
    @State private var page: GameHubPage?
    @State private var steamSignIn = false
    @State private var settingsModal = false
    @State private var settingsColumn = 0
    @State private var dialog: GameHubDialog.Content?

    private var accent: Color { ConsoleHome.accent(accentIndex) }
    private var modal: Bool {
        selected != nil || browser || onboarding.presented || settingsModal || dialog != nil || steamSignIn || model.error != nil
    }
    private var jitProblem: JITCoordinator.ConnectionProblem? {
        jit.connectionProblem.flatMap { model.error == $0.message ? $0 : nil }
    }
    private var myGames: [LibraryEntry] { games.filter { $0.steamAppID == nil } }
    private var focusedCover: LibraryEntry? { games.indices.contains(coverIndex) ? games[coverIndex] : nil }

    var body: some View {
        ZStack {
            if let page {
                pageView(page).transition(.opacity)
            } else {
                backdrop
                VStack(spacing: 0) {
                    GameHubTopBar(tab: tab, actions: GameHubAction.forTab(tab), select: { switchTab(to: $0) }, perform: perform)
                        .padding(.horizontal, 34).padding(.top, 8)
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let dialog {
                GameHubDialog(content: dialog) { self.dialog = nil }.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: page)
        .animation(.easeInOut(duration: 0.15), value: dialog)
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
        .fullScreenCover(isPresented: $onboarding.presented) { OnboardingView() }
        .sheet(isPresented: $browser) {
            NavigationStack { ExecutableBrowser(folder: LibraryModel.drive) { entry in
                model.save(entry); browser = false; selected = entry
            } }
        }
        .sheet(isPresented: $steamSignIn) { SteamSignInView() }
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
            switch tab {
            case .library:
                if shelf == nil, let entry = focusedCover { GameHubCoverBackdrop(entry: entry) }
            case .home:
                LinearGradient(colors: [Color(red: 0.32, green: 0.07, blue: 0.1).opacity(0.85), Color(white: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .community, .ranking, .profile:
                LinearGradient(colors: [GameHub.background, Color(white: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
            GameHubHomePage(section: $homeSection, games: games, open: { selected = $0 }, play: { entry in launch(games, at: games.firstIndex { $0.id == entry.id } ?? -1) },
                            openSteamApp: openSteamApp)
                .transition(.opacity)
        case .ranking:
            GameHubRankingPage(open: openSteamApp).transition(.opacity)
        case .profile:
            GameHubProfilePage(games: games.count, signIn: askSteamSignIn, openSteam: { switchTab(to: .library); openShelf(.steam) },
                               community: { switchTab(to: .community) })
                .transition(.opacity)
        }
    }

    @ViewBuilder private func pageView(_ page: GameHubPage) -> some View {
        switch page {
        case .settings:
            GameHubFullPage(title: "Settings", glow: Color(red: 0.16, green: 0.2, blue: 0.36), close: { self.page = nil }) {
                ConsoleSettingsPage(active: !modal, modal: $settingsModal, column: $settingsColumn, accent: accent,
                                    enableJIT: enableJIT, startDock: startDock, addGame: { browser = true },
                                    exit: { self.page = nil }, gamehub: true)
                    .padding(.horizontal, 10)
            }
        case .downloads:
            GameHubFullPage(title: "Download Manager", glow: Color(red: 0.3, green: 0.16, blue: 0.5), close: { self.page = nil }) {
                GameHubDownloadsPage()
            }
        }
    }

    @ViewBuilder private var libraryContent: some View {
        switch shelf {
        case nil:
            GameHubLibraryPage(games: games, coverIndex: coverIndex, tileIndex: tileIndex, row: libraryRow,
                               focusCover: { i in
                                   if coverIndex == i { launch(games, at: i) }
                                   else { withAnimation(GameHubLibraryPage.motion) { coverIndex = i; libraryRow = 0 } }
                               },
                               details: { details(games, at: coverIndex) },
                               play: { launch(games, at: coverIndex) },
                               tile: { i in tileIndex = i; libraryRow = 1; openShelf(GameHubShelf.allCases[i]) })
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
                GameHubEmptyState(title: "Epic Games Store",
                                  message: "Signing in to Epic is not supported yet. Games you installed elsewhere can be added with Import.",
                                  action: ("Import", { browser = true }))
            }
        case .importGame?:
            EmptyView()
        }
    }

    // MARK: Navigation

    private func perform(_ action: GameHubAction) {
        switch action {
        case .search: CommunityModel.shared.searching.toggle()
        case .layoutSwitch: UserDefaults.standard.set(false, forKey: ConsoleHome.key)
        case .notifications:
            dialog = .init(icon: "bell.badge", title: "Notifications", message: "You're all caught up.", primary: nil)
        case .controller, .settings: settingsColumn = 0; page = .settings
        case .scan: steamSignIn = true
        case .downloads: page = .downloads
        }
    }

    private func askSteamSignIn() {
        if SteamSignIn.isSignedIn { switchTab(to: .library); openShelf(.steam); return }
        dialog = .init(icon: "person.crop.circle.badge.plus", title: "Log in to Steam",
                       message: "Bind your Steam account to see your game library and play it here.",
                       primary: ("Login", { steamSignIn = true }))
    }

    private func switchTab(to newTab: GameHubTab) {
        guard newTab != tab else { if newTab == .library { closeShelf() }; return }
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.18)) { tab = newTab }
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

    /// A Steam app from the charts or the store: its library entry when it is installed, else its store page.
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
        let coverID = focusedCover.map { ConsoleHomeView.key($0) }
        games = list
        coverIndex = coverID.flatMap { id in list.firstIndex { ConsoleHomeView.key($0) == id } } ?? min(coverIndex, max(0, list.count - 1))
        myGamesIndex = min(myGamesIndex, myGames.count)
    }

    /// Plays a game that is not Steam's; a Steam game opens its details page, which
    /// checks its download and sign-in first. An index past the end adds a game.
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
        if page != nil {
            // Settings takes its own commands and calls exit on B; Downloads closes on B.
            if page == .downloads, command == "back" { page = nil }
            return
        }
        switch command {
        case "tab": cycleTab(1); return
        case "tabPrev": cycleTab(-1); return
        case "menu": settingsColumn = 0; page = .settings; return
        default: break
        }
        switch tab {
        case .library:
            switch shelf {
            case nil: libraryCommand(command)
            case .myGames?:
                if command == "back" { closeShelf() } else { move(command, index: $myGamesIndex, in: myGames, columns: myGamesColumns) }
            default:
                if command == "back" { closeShelf() }
            }
        case .home:
            switch command {
            case "left": homeSection = max(0, homeSection - 1)
            case "right": homeSection = min(2, homeSection + 1)
            case "back": switchTab(to: .library)
            default: break
            }
        case .community, .ranking, .profile: if command == "back" { switchTab(to: .library) }
        }
    }

    private func libraryCommand(_ command: String) {
        let motion = GameHubLibraryPage.motion
        if libraryRow == 0 && !games.isEmpty {
            switch command {
            case "left": withAnimation(motion) { coverIndex = max(0, coverIndex - 1) }
            case "right": withAnimation(motion) { coverIndex = min(games.count - 1, coverIndex + 1) }
            case "down": withAnimation(motion) { libraryRow = 1 }
            case "accept": launch(games, at: coverIndex)
            case "x": details(games, at: coverIndex)
            case "add": browser = true
            default: break
            }
        } else {
            switch command {
            case "left": tileIndex = max(0, tileIndex - 1)
            case "right": tileIndex = min(GameHubShelf.allCases.count - 1, tileIndex + 1)
            case "up": if !games.isEmpty { withAnimation(motion) { libraryRow = 0 } }
            case "accept": openShelf(GameHubShelf.allCases[tileIndex])
            case "add": browser = true
            default: break
            }
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
    let actions: [GameHubAction]
    let select: (GameHubTab) -> Void
    let perform: (GameHubAction) -> Void

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
                ForEach(actions, id: \.self) { action in
                    Button { perform(action) } label: {
                        if action == .layoutSwitch { GameHubLayoutSwitchIcon().frame(width: 22, height: 22) }
                        else { Image(systemName: action.icon) }
                    }
                    .accessibilityLabel(action.label)
                }
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

/// Time, network and battery, as GameHub draws them.
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
            Image(systemName: network.wifi ? "wifi" : network.online ? "cellularbars" : "wifi.slash")
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

/// The focused game's art on the right of the page, fading into the dark on the left.
struct GameHubCoverBackdrop: View {
    let entry: LibraryEntry
    var body: some View {
        GeometryReader { geo in
            LibraryArtwork(entry: entry, backdrop: true)
                .frame(width: geo.size.width * 0.62, height: geo.size.height)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.85), location: 0.45),
                                             .init(color: .black, location: 1)], startPoint: .leading, endPoint: .trailing))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay(LinearGradient(colors: [.clear, GameHub.background.opacity(0.9)], startPoint: .center, endPoint: .bottom))
                .id(ConsoleHomeView.key(entry))
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: ConsoleHomeView.key(entry))
    }
}

/// Library: the row of covers (games before the focused one slide off to the
/// left, the focused one is larger and its title sits beside it), View Details
/// and the menu, then the four tiles. With no games, only the tiles.
struct GameHubLibraryPage: View {
    let games: [LibraryEntry]
    let coverIndex: Int
    let tileIndex: Int
    /// 0: the covers have the controller's focus, 1: the tiles.
    let row: Int
    let focusCover: (Int) -> Void
    let details: () -> Void
    let play: () -> Void
    let tile: (Int) -> Void

    static var motion: Animation? { UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.32, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            let big = min(310, max(170, geo.size.height * 0.52))
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if !games.isEmpty {
                            covers(height: big, width: geo.size.width).id("covers")
                            HStack(spacing: 16) {
                                Button(action: details) {
                                    Text("View Details").font(.system(size: 17, weight: .semibold))
                                        .frame(width: 168, height: 44)
                                        .background(Capsule().fill(GameHub.button))
                                        .overlay(Capsule().stroke(row == 0 && GCController.current != nil ? Color.white.opacity(0.8) : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                Menu {
                                    Button("Play", systemImage: "play.fill", action: play)
                                    Button("View Details", systemImage: "info.circle", action: details)
                                } label: {
                                    Image(systemName: "line.3.horizontal").font(.system(size: 18, weight: .semibold))
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(GameHub.button))
                                }
                                .accessibilityLabel("More")
                            }
                        }
                        GameHubShelves(focus: row == 1 || games.isEmpty ? tileIndex : -1, tap: tile).id("tiles")
                    }
                    .padding(.horizontal, 34).padding(.top, 12).padding(.bottom, 24)
                }
                .onChange(of: row) { _, value in
                    withAnimation(Self.motion) { reader.scrollTo(value == 1 ? "tiles" : "covers", anchor: .center) }
                }
            }
        }
    }

    private func covers(height big: CGFloat, width: CGFloat) -> some View {
        let small = big * 0.8
        let rest = Array(games.indices.dropFirst(coverIndex + 1))
        return HStack(alignment: .top, spacing: 14) {
            cover(games[coverIndex], width: big * 0.667, height: big, focused: true)
                .onTapGesture { focusCover(coverIndex) }
            // The smaller covers after it, with the focused game's title under them.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rest, id: \.self) { i in
                        cover(games[i], width: small * 0.667, height: small, focused: false)
                            .onTapGesture { focusCover(i) }
                    }
                }
                .frame(height: rest.isEmpty ? 0 : small, alignment: .top)
                Text(games[coverIndex].title).font(.system(size: 19, weight: .bold)).lineLimit(1)
                    .padding(.top, rest.isEmpty ? big - 30 : 14)
                    .id("title-" + ConsoleHomeView.key(games[coverIndex]))
                    .transition(.opacity)
            }
        }
        .frame(width: width - 68, alignment: .leading)
        .frame(height: big, alignment: .top)
        .clipped()
        .animation(Self.motion, value: coverIndex)
    }

    private func cover(_ entry: LibraryEntry, width: CGFloat, height: CGFloat, focused: Bool) -> some View {
        LibraryArtwork(entry: entry)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused && row == 0 && GCController.current != nil ? Color.white : Color.white.opacity(0.06), lineWidth: focused ? 2 : 1))
            .shadow(color: .black.opacity(focused ? 0.5 : 0.3), radius: focused ? 14 : 6, y: 4)
            .contentShape(Rectangle())
            .accessibilityLabel(entry.title)
            .accessibilityAddTraits(.isButton)
    }
}

struct GameHubShelves: View {
    let focus: Int
    let tap: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(GameHubShelf.allCases) { shelf in
                Button { tap(shelf.rawValue) } label: {
                    VStack(spacing: 10) {
                        GameHubShelfIcon(shelf: shelf).frame(width: 34, height: 34)
                        Text(shelf.title).font(.system(size: 17, weight: .regular))
                    }
                    .frame(maxWidth: .infinity).frame(height: 100)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GameHub.tile))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(focus == shelf.rawValue && GCController.current != nil ? Color.white.opacity(0.85) : GameHub.tileStroke,
                                lineWidth: focus == shelf.rawValue && GCController.current != nil ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shelf.title)
            }
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
            GameHubSteamMark()
        case .epic:
            GameHubEpicMark().frame(width: 27, height: 32)
        case .importGame:
            Image(systemName: "plus").font(.system(size: 32, weight: .thin))
        }
    }
}

struct GameHubSteamMark: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.07, green: 0.16, blue: 0.33), Color(red: 0.0, green: 0.42, blue: 0.75)],
                                         startPoint: .top, endPoint: .bottom))
            Image(systemName: "gearshape.2.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
        }
    }
}

struct GameHubEpicMark: View {
    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 0, bottomTrailing: 0, topTrailing: 3))
        ZStack {
            shape.fill(Color(white: 0.2)).overlay(shape.stroke(Color(white: 0.4), lineWidth: 0.6))
            VStack(spacing: 0) {
                Text("EPIC").font(.system(size: 10, weight: .black)).tracking(-0.3)
                Text("GAMES").font(.system(size: 4.5, weight: .heavy))
            }.foregroundStyle(.white).offset(y: -2)
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
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 34).padding(.top, 6)
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
