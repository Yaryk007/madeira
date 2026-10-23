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
    /// GameHub's own nav icon (GameHubAssets.swift).
    func asset(selected: Bool) -> String {
        let base: String
        switch self {
        case .library: base = "gh-nav-library"
        case .community: base = "gh-nav-community"
        case .home: base = "gh-nav-home"
        case .ranking: base = "gh-nav-ranking"
        case .profile: base = "gh-nav-profile"
        }
        return selected ? base + "-on" : base
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
    /// GameHub's own icon (GameHubAssets.swift).
    var asset: String {
        switch self {
        case .search: return "gh-search"
        case .layoutSwitch: return "gh-layout-switch"
        case .notifications: return "gh-bell"
        case .controller: return "gh-gamepad"
        case .scan: return "gh-qr"
        case .downloads: return "gh-download"
        case .settings: return "gh-settings"
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
    @State private var myGamesTab = 0
    @State private var steamTab = 0
    @State private var steamIndex = 0
    @State private var homeSection = 0
    @State private var selected: LibraryEntry?
    @State private var browser = false
    @State private var page: GameHubPage?
    @State private var steamSignIn = false
    @State private var settingsModal = false
    /// The Settings category a button opens (the controller button: Peripherals).
    @State private var settingsCategory: GameHubSettingsPage.Category = .account
    @State private var dialog: GameHubDialog.Content?
    /// GameHub's Library popups: ≡'s menu (at its button), View Details, Remove Game.
    @State private var moreAnchor: CGRect?
    @State private var detailsEntry: LibraryEntry?
    @State private var removeEntry: LibraryEntry?
    @State private var removeFiles = true
    /// The backdrop follows the focused cover a moment after the row settles.
    @State private var backdropEntry: LibraryEntry?
    @StateObject private var importer = GameImportModel()
    /// First run: "No game files detected", then the Import tile's spotlight.
    @AppStorage("gamehubFirstRunDone") private var firstRunDone = false
    @AppStorage("gamehubImportHintDone") private var importHintDone = false

    private var accent: Color { ConsoleHome.accent(accentIndex) }
    private var modal: Bool {
        selected != nil || moreAnchor != nil || detailsEntry != nil || removeEntry != nil || browser || onboarding.presented || settingsModal || dialog != nil || steamSignIn || model.error != nil
            || importer.menu || importer.picker != nil || importer.pendingExe != nil || importer.progress != nil || !importer.choices.isEmpty
    }
    private var jitProblem: JITCoordinator.ConnectionProblem? {
        jit.connectionProblem.flatMap { model.error == $0.message ? $0 : nil }
    }
    private var myGames: [LibraryEntry] { games.filter { $0.steamAppID == nil && $0.desktop != true } }
    private var steamGamesList: [LibraryEntry] { games.filter { $0.steamAppID != nil } }
    private var showFirstRun: Bool { !firstRunDone && !onboarding.presented && !games.contains { $0.desktop != true } }
    private var showImportHint: Bool { firstRunDone && !importHintDone && tab == .library && shelf == nil && page == nil && !modal }
    private var focusedCover: LibraryEntry? { games.indices.contains(coverIndex) ? games[coverIndex] : nil }

    var body: some View {
        ZStack {
            if let page {
                pageView(page).transition(.opacity)
            } else {
                backdrop
                // GameHub's top bar is fixed and clear: Library's page scrolls under it.
                // Margins count from the screen edge, as on GameHub's full-screen pages.
                ZStack(alignment: .top) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, tab == .library ? 0 : GameHubTopBar.height)
                    if !(tab == .library && shelf != nil) {
                        GameHubTopBar(tab: tab, actions: GameHubAction.forTab(tab), select: { switchTab(to: $0) }, perform: perform)
                            .padding(.horizontal, GameHub.margin)
                    }
                }
                .ignoresSafeArea(.container, edges: .horizontal)
                .overlayPreferenceValue(GameHubImportAnchor.self) { anchor in
                    GeometryReader { geo in
                        if showImportHint, let anchor {
                            GameHubImportHint(hole: geo[anchor], open: { importHintDone = true; importer.start() },
                                              done: { importHintDone = true })
                                .transition(.opacity)
                        }
                    }
                    .ignoresSafeArea()
                }
                if showFirstRun {
                    GameHubFirstRunPage(selectFolder: { firstRunDone = true; importer.picker = .folder(start: nil, exeName: nil) },
                                        explore: { firstRunDone = true })
                        .transition(.opacity)
                }
            }
            GameHubControllerToast().padding(.top, 62).padding(.trailing, GameHub.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
            GameImportOverlay(model: importer, browse: { browser = true })
            if let dialog {
                GameHubDialog(content: dialog) { self.dialog = nil }.transition(.opacity)
            }
            if let anchor = moreAnchor, games.indices.contains(coverIndex) {
                let entry = games[coverIndex]
                GameHubMoreMenu(anchor: anchor, choose: { action in moreAnchor = nil; gameAction(action, entry) },
                                dismiss: { moreAnchor = nil })
            }
            if let entry = detailsEntry {
                GameHubDetailsCard(entry: entry, launch: { launch([entry], at: 0) },
                                   choose: { action in detailsEntry = nil; gameAction(action, entry) },
                                   dismiss: { detailsEntry = nil })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if let entry = removeEntry {
                let target = GameFiles.target(entry)
                let size = target.map { ByteCountFormatter.string(fromByteCount: GameFiles.size($0), countStyle: .file) }
                GameHubNotice(message: "Remove this game from your library?",
                              option: size.map { ("Also delete the game's files (\($0))", $removeFiles) },
                              confirmed: { removeGame(entry, files: target != nil && removeFiles) },
                              dismiss: { removeEntry = nil })
                    .transition(.opacity)
            }
            GameHubSplash()
        }
        .animation(.easeInOut(duration: 0.18), value: page)
        .animation(.easeInOut(duration: 0.15), value: dialog)
        .animation(.easeOut(duration: 0.16), value: moreAnchor != nil)
        .animation(.easeOut(duration: 0.18), value: detailsEntry?.id)
        .animation(.easeOut(duration: 0.15), value: removeEntry?.id)
        .onChange(of: coverIndex) { _, _ in
            // GameHub swaps the backdrop once the row has moved, with a crossfade.
            let target = focusedCover
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if focusedCover?.id == target?.id { backdropEntry = target }
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
            GameHubPerformance.applyRecommendedIfNeeded()
            onboarding.presentIfNeeded()
            steamGames.refresh()
            rebuildGames()
            importer.added = { entry in model.save(entry); selected = entry }
            LogStore.shared.log("[gamehub-home] shown games=\(games.count)")
        }
    }

    @ViewBuilder private var backdrop: some View {
        ZStack {
            GameHub.background
            switch tab {
            case .library:
                if shelf == nil, !games.isEmpty { GameHubLibraryBackdrop(entry: backdropEntry ?? focusedCover) }
            case .home:
                LinearGradient(colors: [Color(red: 0.32, green: 0.07, blue: 0.1).opacity(0.85), Color(white: 0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .ranking:
                LinearGradient(colors: [Color(red: 51 / 255, green: 38 / 255, blue: 35 / 255), Color(red: 30 / 255, green: 25 / 255, blue: 24 / 255),
                                        Color(red: 18 / 255, green: 17 / 255, blue: 19 / 255)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .community, .profile:
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
            GameHubFullPage(title: "Settings", glow: Color(red: 30 / 255, green: 32 / 255, blue: 43 / 255), glowCenter: .center, close: { self.page = nil }) {
                GameHubSettingsPage(active: !modal, modal: $settingsModal, initial: settingsCategory,
                                    enableJIT: enableJIT, startDock: startDock, exit: { self.page = nil })
            }
        case .downloads:
            GameHubFullPage(title: "Download Manager", glow: Color(red: 0.3, green: 0.16, blue: 0.5).opacity(0.75), close: { self.page = nil }) {
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
                               details: { if games.indices.contains(coverIndex) { detailsEntry = games[coverIndex] } },
                               more: { moreAnchor = $0 },
                               tile: { i in tileIndex = i; libraryRow = 1; openShelf(GameHubShelf.allCases[i]) })
        case .myGames?:
            GameHubGamesPage(title: "My Games", tabs: ["PC Games", "Retro Games"], tab: $myGamesTab,
                             search: { CommunityModel.shared.searching.toggle() },
                             settings: { settingsCategory = .peripherals; page = .settings }, back: closeShelf) {
                if myGamesTab == 0 && !myGames.isEmpty {
                    GameHubGameGrid(games: myGames, index: myGamesIndex, columns: $myGamesColumns,
                                    tap: { tapped($0, focus: $myGamesIndex, in: myGames) })
                } else {
                    GameHubEmptyState(title: myGamesTab == 0 ? "No games yet" : "No retro games",
                                      message: myGamesTab == 0 ? "Games you import show up here." : "Retro games are not supported in this build.",
                                      action: myGamesTab == 0 ? ("Import", { importer.start() }) : nil)
                }
            }
        case .steam?:
            GameHubGamesPage(title: "Steam", tabs: SteamSignIn.isSignedIn ? ["Installed", "All Games"] : [], tab: $steamTab,
                             sortTitle: SteamSignIn.isSignedIn ? "Recently Played" : nil, back: closeShelf) {
                if !SteamSignIn.isSignedIn {
                    GameHubSteamUnbound(bind: { steamSignIn = true })
                } else if steamTab == 0 && !steamGamesList.isEmpty {
                    GameHubGameGrid(games: steamGamesList, index: steamIndex, columns: $myGamesColumns,
                                    tap: { tapped($0, focus: $steamIndex, in: steamGamesList) })
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            SteamGamesSection(search: "", layout: "cards", sort: "played", width: geo.size.width - 120,
                                              part: steamTab == 0 ? .all : .notInstalled, open: { selected = $0 })
                                .padding(.leading, 62).padding(.trailing, 58).padding(.vertical, 8)
                        }
                        .refreshable { await SteamGamesSection.refresh() }
                    }
                }
            }
        case .epic?:
            GameHubShelfPage(title: "Epic", back: closeShelf) {
                GameHubEmptyState(title: "Epic Games Store",
                                  message: "Signing in to Epic is not supported yet. Games you installed elsewhere can be added with Import.",
                                  action: ("Import", { importer.start() }))
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
        case .controller: settingsCategory = .peripherals; page = .settings
        case .settings: settingsCategory = .account; page = .settings
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
        if target == .importGame { importer.start(); return }
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

    /// Plays a game. A Steam game first passes the checks its details page makes
    /// (download finished, Steam client and sign-in, or its program for a direct
    /// start); what blocks it is shown with a way to its details. An index past
    /// the end adds a game.
    private func launch(_ list: [LibraryEntry], at index: Int) {
        guard list.indices.contains(index) else { importer.start(); return }
        var entry = list[index]
        if let appID = entry.steamAppID {
            if let blocker = Self.steamBlocker(entry, appID: appID) {
                dialog = .init(icon: "exclamationmark.triangle.fill", title: entry.title, message: blocker,
                               primary: ("View Details", { selected = entry }))
                return
            }
            // A Steam game played for the first time gets its recommended settings, as its details page gives them.
            _ = GameRecommendations.prepare(&entry, new: !model.entries.contains { $0.id == entry.id })
        }
        LogStore.shared.log("[gamehub-home] play \(entry.title)")
        model.save(entry); play(entry)
    }

    static func steamBlocker(_ entry: LibraryEntry, appID: Int) -> String? {
        if SteamOwnedLibrary.shared.downloads[appID] != nil {
            return "This game's update has not finished. Resume it and wait for it to complete before playing."
        }
        let installed = SteamGamesModel.shared.games.first { $0.id == appID }?.installed ?? false
        if entry.startsSteamGameDirectly { return SteamDirectStart.blocker(installed: installed, program: entry.steamProgram) }
        return SteamGamesRules.blocker(installed: installed, client: MadeiraDock.clientInstalled, signedIn: SteamSignIn.isSignedIn)
    }

    /// ≡ and View Details' actions. PC Game Settings, Edit Info and Keys & Layout
    /// open the game's settings page; Add to Desktop copies its Home Screen link.
    private func gameAction(_ action: GameHubGameAction, _ entry: LibraryEntry) {
        switch action {
        case .settings, .editInfo, .keys: selected = entry
        case .remove:
            removeFiles = GameFiles.target(entry) != nil
            removeEntry = entry
        case .desktop:
            UIPasteboard.general.string = ShortcutRouter.link(for: entry.windowsPath)
            dialog = .init(icon: "square.and.arrow.down.on.square", title: "Add to Desktop",
                           message: "The game's link is copied. In the Shortcuts app: new shortcut, Open URLs, paste the link, then Share › Add to Home Screen.",
                           primary: nil)
        }
    }

    private func removeGame(_ entry: LibraryEntry, files: Bool) {
        if let appID = entry.steamAppID, entry.steamAppID != nil {
            model.remove(entry.id)
            LogStore.shared.log("[gamehub-remove] Steam app \(appID): library entry removed, Steam keeps its files")
            return
        }
        do {
            let freed = try GameFiles.remove(entry, files: files, model: model)
            if freed > 0 {
                dialog = .init(icon: "checkmark.circle.fill", title: "Game removed",
                               message: "\(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)) freed.", primary: nil)
            }
        } catch {
            dialog = .init(icon: "exclamationmark.triangle.fill", title: "Couldn't delete the files",
                           message: error.localizedDescription, primary: nil)
        }
    }

    private func details(_ list: [LibraryEntry], at index: Int) {
        guard list.indices.contains(index) else { importer.start(); return }
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
        case "menu": settingsCategory = .account; page = .settings; return
        default: break
        }
        switch tab {
        case .library:
            switch shelf {
            case nil: libraryCommand(command)
            case .myGames?:
                if command == "back" { closeShelf() } else { move(command, index: $myGamesIndex, in: myGames, columns: myGamesColumns) }
            case .steam?:
                if command == "back" { closeShelf() } else if steamTab == 0 { move(command, index: $steamIndex, in: steamGamesList, columns: myGamesColumns) }
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
            case "add": importer.start()
            default: break
            }
        } else {
            switch command {
            case "left": tileIndex = max(0, tileIndex - 1)
            case "right": tileIndex = min(GameHubShelf.allCases.count - 1, tileIndex + 1)
            case "up": if !games.isEmpty { withAnimation(motion) { libraryRow = 0 } }
            case "accept": openShelf(GameHubShelf.allCases[tileIndex])
            case "add": importer.start()
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
        case "add": importer.start(); return
        default: return
        }
        next = min(max(next, 0), list.count)
        guard next != index.wrappedValue else { return }
        withAnimation(ConsoleHomeView.motion) { index.wrappedValue = next }
    }
}

// MARK: - Top bar

struct GameHubTopBar: View {
    /// GameHub's bar: icons centred 27 pt from the top.
    static let height: CGFloat = 54
    let tab: GameHubTab
    let actions: [GameHubAction]
    let select: (GameHubTab) -> Void
    let perform: (GameHubAction) -> Void
    @ObservedObject private var pads = GameHubControllers.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 23) {
                ForEach(GameHubTab.allCases) { t in
                    Button { select(t) } label: {
                        HStack(spacing: 6) {
                            GHImage(name: t.asset(selected: t == tab), fallback: t.icon(selected: t == tab)).frame(width: 23, height: 23)
                            if t == tab { Text(t.title).font(.system(size: 20, weight: .bold)).fixedSize() }
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
            HStack(spacing: 18) {
                ForEach(actions, id: \.self) { action in
                    Button { perform(action) } label: {
                        if GHAsset.has(action.asset) { GHImage(name: action.asset).frame(width: 23, height: 23) }
                        else if action == .layoutSwitch { GameHubLayoutSwitchIcon().frame(width: 22, height: 22) }
                        else if action == .controller, pads.name != nil { Image(systemName: "gamecontroller.fill") }
                        else { Image(systemName: action.icon) }
                    }
                    .accessibilityLabel(action.label)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 20, weight: .regular))
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 14).padding(.horizontal, 11)
            GameHubStatus()
        }
        .frame(height: Self.height)
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
        HStack(spacing: 10) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .monospacedDigit()
                    .onChange(of: context.date) { _, _ in battery = UIDevice.current.batteryLevel }
            }
            if GHAsset.has("gh-wifi") {
                GHImage(name: network.wifi ? "gh-wifi" : network.online ? "gh-5g" : "gh-no-network").frame(width: 23, height: 23)
            } else {
                Image(systemName: network.wifi ? "wifi" : network.online ? "cellularbars" : "wifi.slash")
                    .font(.system(size: 17, weight: .semibold))
            }
            if battery >= 0 {
                HStack(spacing: 4) {
                    if GHAsset.has("gh-battery-5") {
                        GHImage(name: "gh-battery-\(battery > 0.8 ? 5 : battery > 0.6 ? 4 : battery > 0.4 ? 3 : battery > 0.2 ? 2 : 1)")
                            .frame(width: 23, height: 23)
                            .colorMultiply(battery <= 0.15 ? .red : .white)
                    } else {
                        Image(systemName: battery > 0.9 ? "battery.100percent" : battery > 0.6 ? "battery.75percent"
                              : battery > 0.35 ? "battery.50percent" : battery > 0.15 ? "battery.25percent" : "battery.0percent")
                            .font(.system(size: 20))
                            .foregroundStyle(battery <= 0.15 ? Color.red : Color.white)
                    }
                    Text("\(Int((battery * 100).rounded()))%").monospacedDigit()
                }
            }
        }
        .font(.system(size: 17, weight: .semibold))
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

struct GameHubImportAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// The first run's spotlight on Import: the page dims around the tile, a hand
/// points at it, "Click here to import games" and Got it beside.
struct GameHubImportHint: View {
    let hole: CGRect
    let open: () -> Void
    let done: () -> Void
    @State private var bob = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.72)
                .mask {
                    ZStack {
                        Rectangle()
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .frame(width: hole.width + 8, height: hole.height + 8)
                            .position(x: hole.midX, y: hole.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .onTapGesture(perform: done)
            Color.clear.contentShape(Rectangle())
                .frame(width: hole.width, height: hole.height)
                .position(x: hole.midX, y: hole.midY)
                .onTapGesture(perform: open)
            Image(systemName: "hand.point.up.left.fill").font(.system(size: 40)).foregroundStyle(.white)
                .shadow(radius: 6)
                .position(x: hole.midX, y: hole.maxY + 42 + (bob ? -6 : 0))
            HStack(spacing: 12) {
                Text("Click here to import games").font(.system(size: 17))
                Button(action: done) {
                    Text("Got it").font(.system(size: 14)).padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            .fixedSize()
            .position(x: min(hole.midX, UIScreen.main.bounds.width - 170), y: hole.maxY + 100)
        }
        .foregroundStyle(.white)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { bob = true } }
    }
}

/// The first run with no games, as GameHub's after sign-in: no game files
/// detected, Select Folder Manually, or explore first.
struct GameHubFirstRunPage: View {
    let selectFolder: () -> Void
    let explore: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.05, blue: 0.12), Color(red: 0.03, green: 0.1, blue: 0.24)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
            RadialGradient(colors: [Color(red: 0.25, green: 0.4, blue: 0.7).opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 110, height: 70).offset(y: -18)
                    Image(systemName: "folder.fill").font(.system(size: 120))
                        .foregroundStyle(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                }
                .frame(height: 120)
                Text("No game files detected").font(.system(size: 18)).padding(.top, 8)
                Text("Choose your game's folder; GameHub copies it in and adds it to your library.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                Button(action: selectFolder) {
                    Text("Select Folder Manually").font(.system(size: 18))
                        .frame(width: 340, height: 54)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(GameHub.postBlue))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain).padding(.top, 14)
                Button("Explore other games", action: explore).font(.system(size: 17)).foregroundStyle(GameHub.link).padding(.top, 8)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
    }
}

struct GameHubShelfIcon: View {
    let shelf: GameHubShelf
    private var asset: String {
        switch shelf {
        case .myGames: return "gh-entry-mygames"
        case .steam: return "gh-entry-steam"
        case .epic: return "gh-entry-epic"
        case .importGame: return "gh-import"
        }
    }
    var body: some View {
        if GHAsset.has(asset) {
            GHImage(name: asset).frame(width: 34, height: 34)
        } else {
            drawn
        }
    }
    @ViewBuilder private var drawn: some View {
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
            .padding(.horizontal, GameHub.margin).padding(.top, 6)
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "Device connected · <name>" for a few seconds after a controller connects
/// (or "Device disconnected"), as GameHub shows it.
struct GameHubControllerToast: View {
    @ObservedObject private var pads = GameHubControllers.shared
    var body: some View {
        ZStack {
            if let toast = pads.toast {
                GameHubPadBadge(title: toast.connected ? "Device connected" : "Device disconnected", name: toast.name, connected: toast.connected)
                    .id(toast.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pads.toast?.id)
    }
}
