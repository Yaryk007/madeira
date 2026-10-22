import SwiftUI
import GameController
import UIKit
import UserNotifications

/// GamehubiOS's switches that only this front end has.
enum GameHubPrefs {
    static let keySoundKey = "gamehubKeySound"
    static let buttonHapticsKey = "gamehubButtonHaptics"
    static let launchHapticKey = "gamehubLaunchHaptic"
    /// Key Sound › Controller Buttons: the touch controls' haptic taps.
    static var buttonHaptics: Bool { flag(keySoundKey) && flag(buttonHapticsKey) }
    /// Key Sound › Game Launch: a haptic when a game's first frame shows.
    static var launchHaptic: Bool { flag(keySoundKey) && flag(launchHapticKey) }
    /// Peripherals › Touchpad opens the menu: a PS4/PS5 controller's touchpad
    /// click opens and closes the in-game menu instead of reaching the game.
    static let touchpadMenuKey = "gamehubTouchpadMenu"
    static var touchpadMenu: Bool { flag(touchpadMenuKey) }
    /// Peripherals › Controller type, read at each game's start
    /// (GamepadInput.configuredPadMode): "auto" shows a PlayStation controller to
    /// games as a DualSense and any other as an Xbox (XInput) controller.
    static let controllerTypeKey = "gamehubControllerType"
    static var controllerType: String { UserDefaults.standard.string(forKey: controllerTypeKey) ?? "auto" }
    static let controllerTypes = [("auto", "Auto"), ("xbox", "Xbox"), ("playstation", "PlayStation")]
    private static func flag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// GameHub's Settings page: categories in grouped cards on the left (a bar
/// beside the selected one), its panel of grouped rows on the right. The
/// categories follow GameHub's; each holds Madeira's own options. Privacy has
/// no Madeira counterpart, so its place holds JIT & System.
struct GameHubSettingsPage: View {
    enum Category: String, CaseIterable, Identifiable {
        case account, peripherals, mode, language, notifications, keySound, system, storage, downloads, feedback, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .account: return "Account"
            case .peripherals: return "Peripherals"
            case .mode: return "Mode"
            case .language: return "Language"
            case .notifications: return "Notifications"
            case .keySound: return "Key Sound"
            case .system: return "JIT & System"
            case .storage: return "Storage"
            case .downloads: return "Download Tasks"
            case .feedback: return "Feedback & Suggestions"
            case .about: return "About"
            }
        }
        var icon: String {
            switch self {
            case .account: return "person.crop.circle"
            case .peripherals: return "gamecontroller"
            case .mode: return "iphone.gen3.radiowaves.left.and.right"
            case .language: return "globe"
            case .notifications: return "bell"
            case .keySound: return "speaker.wave.2"
            case .system: return "bolt.shield"
            case .storage: return "internaldrive"
            case .downloads: return "square.and.arrow.down"
            case .feedback: return "ellipsis.bubble"
            case .about: return "info.circle"
            }
        }
        /// GameHub's second card.
        var secondGroup: Bool { self == .feedback || self == .about }
    }

    let active: Bool
    @Binding var modal: Bool
    var initial: Category = .account
    let enableJIT: () -> Void
    let startDock: (DockGame, Bool) -> Void
    let exit: () -> Void
    @ObservedObject private var input = InputSettings.shared
    @ObservedObject private var jitState = LibraryJITState.shared
    @ObservedObject private var steamAccount = SteamSignInModel.shared
    @ObservedObject private var pads = GameHubControllers.shared
    @ObservedObject private var library = LibraryModel.shared
    @AppStorage(ConsoleHome.key) private var gamehubHome = true
    @AppStorage(GameHubPrefs.keySoundKey) private var keySound = true
    @AppStorage(GameHubPrefs.buttonHapticsKey) private var buttonHaptics = true
    @AppStorage(GameHubPrefs.launchHapticKey) private var launchHaptic = true
    @AppStorage(GameHubPrefs.touchpadMenuKey) private var touchpadMenu = true
    @AppStorage(GameHubPrefs.controllerTypeKey) private var controllerType = "auto"
    @State private var category: Category = .account
    /// Controller focus: the categories (nil) or a row of the panel.
    @State private var row: Int?
    @State private var sheet: ConsoleSettingsSheet?
    @State private var developerUI = !FrontendChoice.preferNew
    @State private var restartNotice = false
    @State private var signOut = false
    @State private var notifications: Bool?
    @State private var memoryPlus = false
    @State private var storage: (drive: Int64, free: Int64, cache: Int64)?
    @State private var refresh = 0

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 22) {
                categoryColumn.frame(width: min(300, geo.size.width * 0.3))
                ScrollViewReader { reader in
                    ScrollView(showsIndicators: false) {
                        panel.padding(.bottom, 30).id(category)
                    }
                    .onChange(of: row) { _, value in
                        if let value { withAnimation(ConsoleHomeView.motion) { reader.scrollTo("row-\(value)", anchor: .center) } }
                    }
                }
            }
            .padding(.horizontal, 44)
        }
        .onAppear {
            category = initial
            memoryPlus = EntitlementStatus.check().increasedMemory
            steamAccount.refresh()
            UNUserNotificationCenter.current().getNotificationSettings { s in
                let on = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
                DispatchQueue.main.async { notifications = on }
            }
        }
        .task(id: category) { if category == .storage { await measureStorage() } }
        .sheet(item: $sheet, onDismiss: { refresh += 1 }) { sheetContent($0) }
        .alert("Restart GameHub", isPresented: $restartNotice) {
            Button("OK", role: .cancel) {}
        } message: { Text("Close GameHub from the app switcher and open it again to switch interfaces.") }
        .confirmationDialog("Log out of Steam?", isPresented: $signOut, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { steamAccount.signOut() }
        }
        .onChange(of: sheet) { _, value in modal = value != nil || restartNotice || signOut }
        .onChange(of: restartNotice) { _, value in modal = value || sheet != nil || signOut }
        .onChange(of: signOut) { _, value in modal = value || sheet != nil || restartNotice }
        .onReceive(LibraryController.shared.commands) { handle($0) }
    }

    // MARK: Categories

    private var categoryColumn: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                categoryCard(Category.allCases.filter { !$0.secondGroup })
                categoryCard(Category.allCases.filter(\.secondGroup))
                if steamAccount.accountName != nil {
                    Button { signOut = true } label: {
                        Text("Logout").font(.system(size: 17)).frame(maxWidth: .infinity).frame(height: 58)
                            .background(GameHubCard())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func categoryCard(_ list: [Category]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element) { i, c in
                let selected = c == category
                Button { select(c) } label: {
                    HStack(spacing: 14) {
                        Capsule().fill(selected ? Color.white : .clear).frame(width: 3, height: 15)
                        Image(systemName: c.icon).font(.system(size: 18)).frame(width: 26)
                        Text(c.title).font(.system(size: 17)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.leading, 6).padding(.trailing, 18).frame(minHeight: 62)
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.58))
                    .background(selected && row == nil && GCController.current != nil ? Color.white.opacity(0.07) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < list.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 20).padding(.trailing, 18)
                }
            }
        }
        .background(GameHubCard())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func select(_ c: Category) {
        withAnimation(ConsoleHomeView.motion) { category = c; row = nil }
    }

    // MARK: Panels

    @ViewBuilder private var panel: some View {
        let items = self.items(category)
        VStack(alignment: .leading, spacing: 0) {
            switch category {
            case .peripherals: devices.padding(.bottom, 18)
            case .storage: storageCard.padding(.bottom, 14)
            case .downloads: GameHubDownloadsPage().frame(minHeight: 300)
            case .about:
                VStack(spacing: 10) {
                    GameHubLogo(kind: .wordmark).frame(height: 46)
                    Text("Powered by Madeira").font(.system(size: 13)).foregroundStyle(GameHub.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(GameHubCard(cornerRadius: 22)).padding(.bottom, 18)
            default: EmptyView()
            }
            GameHubRowGroups(items: items, focused: row)
        }
        .padding(.top, 2)
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Devices").font(.system(size: 18))
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08)).frame(width: 64, height: 64)
                    Image(systemName: pads.name == nil ? "gamecontroller.fill" : "gamecontroller.fill").font(.system(size: 24))
                        .foregroundStyle(pads.name == nil ? Color.white : Color(red: 0.45, green: 0.65, blue: 1))
                }
                Text(pads.name ?? "Add device").font(.system(size: 17))
                if pads.name == nil {
                    Text("Pair a controller in iOS Settings › Bluetooth; it shows here once connected.")
                        .font(.system(size: 13)).foregroundStyle(GameHub.secondary).multilineTextAlignment(.center)
                } else {
                    Text("Connected").font(.system(size: 13)).foregroundStyle(GameHub.secondary)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
            .background(GameHubCard(cornerRadius: 22))
            .onTapGesture { if pads.name == nil, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
        }
    }

    private var storageCard: some View {
        let drive = storage?.drive ?? 0, free = storage?.free ?? 0
        let fraction = drive + free > 0 ? Double(drive) / Double(drive + free) : 0
        return HStack(spacing: 34) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 16)
                Circle().trim(from: 0, to: max(0.012, fraction)).stroke(Color(red: 0.35, green: 0.6, blue: 1), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)).font(.system(size: 17))
                    Text("Free").font(.system(size: 12)).foregroundStyle(GameHub.secondary)
                }
            }
            .frame(width: 128, height: 128)
            VStack(alignment: .leading, spacing: 14) {
                (Text("Used ").font(.system(size: 15)) + Text(ByteCountFormatter.string(fromByteCount: drive, countStyle: .file)).font(.system(size: 21)))
                HStack(alignment: .top, spacing: 52) {
                    legend("Installed", ByteCountFormatter.string(fromByteCount: drive, countStyle: .file), Color(red: 0.35, green: 0.6, blue: 1))
                    legend("Free", ByteCountFormatter.string(fromByteCount: free, countStyle: .file), Color.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44).padding(.vertical, 12)
        .background(GameHubCard(cornerRadius: 22))
        .redacted(reason: storage == nil ? .placeholder : [])
    }

    private func legend(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { Circle().fill(color).frame(width: 9, height: 9); Text(title).font(.system(size: 16)) }
            Text(value).font(.system(size: 15)).foregroundStyle(GameHub.secondary).padding(.leading, 17)
        }
    }

    // MARK: Rows

    private func items(_ category: Category) -> [GameHubRow] {
        switch category {
        case .account:
            var list: [GameHubRow] = [
                .header("Account Information"),
                .nav("steam", "Steam account", value: steamAccount.accountName ?? "Not Bound",
                     action: { sheet = steamAccount.accountName == nil ? .steamSignIn : .steam }),
                .nav("jit", "JIT", detail: "Needed to play. Turned on through StikDebug or Built-in StikJIT.",
                     value: jitState.enabled ? "Enabled" : "Enable", action: { if !jitState.enabled { enableJIT() } }),
                .header("Third-Party Accounts"),
                .nav("steam-bind", "Steam", value: steamAccount.accountName == nil ? "Not Bound" : "Bound",
                     action: { sheet = steamAccount.accountName == nil ? .steamSignIn : .steam }),
                .info("epic", "Epic Games", value: "Not supported"),
            ]
            if MadeiraDock.enabled {
                list.insert(.nav("dock", "Madeira Dock", detail: "Valve's Steam client for your Steam games.", action: { sheet = .dock }), at: 3)
            }
            return list
        case .peripherals:
            var list: [GameHubRow] = [.header("Controller")]
            if GamepadInput.keyboardMouseAvailable {
                list.append(.toggle("kbm", "Controller as keyboard & mouse",
                                    detail: "For games without controller support. A game can choose its own in its details.",
                                    $input.padKeyboardMouseDefault))
            }
            for (value, title) in GameHubPrefs.controllerTypes {
                let detail = value == "auto" ? "Games see a PlayStation controller as a DualSense and any other as an Xbox controller."
                    : value == "xbox" ? "Every controller as an Xbox controller (XInput), which nearly every game supports."
                    : "Every controller as a DualSense, for PlayStation button prompts. Games without DualSense support see no controller."
                list.append(.check("type-\(value)", "Controller type: \(title)", detail: detail, controllerType == value, { controllerType = value }))
            }
            list.append(.toggle("touchpad", "Touchpad opens the game menu", detail: "PS4 and PS5 controllers. Off: the touchpad click reaches the game.", $touchpadMenu))
            list.append(.toggle("rsmouse", "Right stick moves the pointer",
                                detail: "In games that read the controller, the right stick also moves the mouse pointer.", $input.padRightStickMouse))
            list.append(.header("Touch & Mouse"))
            let mode = input.touchMode ? 0 : input.relative ? 2 : 1
            list.append(.check("touch", "Touch", detail: "Tap to click where your finger is; hold and move to drag.", mode == 0,
                               { input.touchMode = true; input.relative = false }))
            list.append(.check("trackpad", "Trackpad", detail: "Drag the pointer like a trackpad. Tap to click.", mode == 1,
                               { input.touchMode = false; input.relative = false }))
            list.append(.check("mouselook", "Mouse-look", detail: "Drag for relative mouse movement, for 3D games' cameras.", mode == 2,
                               { input.touchMode = false; input.relative = true }))
            let sensitivity = Binding<Double>(get: { input.relative ? input.sensRel : input.sensAbs },
                                              set: { if input.relative { input.sensRel = $0 } else { input.sensAbs = $0 } })
            list.append(.slider("touch-sens", "Touch sensitivity", sensitivity, 0.1...8, step: 0.1, format: "%.1f"))
            list.append(.slider("mouse-sens", "Mouse sensitivity", $input.sensMouse, 0.25...4, step: 0.05, format: "%.2f"))
            list.append(.toggle("assistive", "Ignore AssistiveTouch clicks", detail: "While a hardware mouse is in use.", $input.ignoreTouchesWithMouse))
            return list
        case .mode:
            return [
                .check("explore", "Explore", detail: "GameHub's home: Library, Community, Home, Ranking and Profile.", gamehubHome, { gamehubHome = true }),
                .check("classic", "Classic library", detail: "Madeira's touch library with its tab bar.", !gamehubHome, { gamehubHome = false }),
                .header("Advanced"),
                .toggle("developer", "Developer interface", detail: "Madeira's original diagnostic screen. Applies after a restart.",
                        Binding(get: { developerUI }, set: { on in developerUI = on; FrontendChoice.choose(new: !on); restartNotice = true })),
            ]
        case .language:
            return [.check("en", "English", detail: "GameHub is in English for now.", true, {})]
        case .notifications:
            return [.toggle("push", "Push Notifications",
                            detail: "Please change this in your phone settings under \"Notifications\" for GameHub",
                            Binding(get: { notifications ?? false }, set: { _ in
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                            }))]
        case .keySound:
            return [
                .toggle("keysound", "Key Sound", detail: "Haptic feedback for the touch controls and game launches", $keySound),
                .header("Sound Type"),
                .toggle("buttons", "Controller Buttons", detail: "Haptic when pressing the on-screen joystick, A/B and other buttons", $buttonHaptics),
                .toggle("launch", "Game Launch", detail: "Haptic when a game starts successfully", $launchHaptic),
            ]
        case .system:
            var list: [GameHubRow] = [
                .nav("jit-setup", "JIT setup", detail: "JIT method, StikDebug, pairing and LocalDevVPN.", action: { sheet = .jit }),
                .info("memory", "Memory+", value: memoryPlus ? "Available" : "Unavailable"),
                .toggle("logging", "Extended logging", detail: "Heavy diagnostics. Leave off unless a run needs explaining.", $input.diagnostics),
            ]
            if MadeiraConfig.flag("MADEIRA_RUNTIME_SETTINGS") {
                list.append(.nav("memsync", "Memory & sync", detail: "JIT pool, video memory, swap and the sync engine.", action: { sheet = .memory }))
                list.append(.nav("display", "Display refresh rate", action: { sheet = .display }))
            }
            list.append(.nav("all", "All settings", detail: "Every madeira.cfg option.", action: { sheet = .allSettings }))
            return list
        case .storage:
            var list: [GameHubRow] = [
                .nav("cache", "Clear Cache", value: storage.map { ByteCountFormatter.string(fromByteCount: $0.cache, countStyle: .file) } ?? "…",
                     action: clearCache),
                .nav("mono", ".NET (Wine Mono)", detail: "For games and launchers built on .NET.", action: { sheet = .mono }),
                .nav("saves", "Save backups", detail: "Back up and restore your saves.", action: { sheet = .saves }),
            ]
            let games = library.entries.filter { $0.desktop != true }
                .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            if !games.isEmpty {
                list.append(.header("Sort: Recently Played"))
                list += games.prefix(30).map { .info("game-\($0.id)", $0.title, value: $0.folderBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—") }
            }
            return list
        case .downloads:
            return []
        case .feedback:
            return [
                .nav("submit", "Submit Feedback", action: { open("https://github.com/Yaryk007/madeira/issues/new") }),
                .nav("history", "Feedback History", action: { open("https://github.com/Yaryk007/madeira/issues") }),
                .nav("website", "Official Website", action: { open("https://github.com/Yaryk007/madeira/tree/gamehub") }),
            ]
        case .about:
            return [
                .info("version", "Version", value: BuildStamp.text),
                .nav("credits", "Credits", action: { sheet = .credits }),
                .nav("madeira", "Madeira", detail: "GameHub runs on Madeira by Will Faust.", action: { open("https://github.com/willfaust/madeira") }),
            ]
        }
    }

    private func open(_ link: String) { if let url = URL(string: link) { UIApplication.shared.open(url) } }

    // MARK: Storage

    private func measureStorage() async {
        let drive = LibraryModel.drive
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let result = await Task.detached(priority: .utility) { () -> (Int64, Int64, Int64) in
            let free = (try? drive.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
            return (Self.size(of: drive), free, Self.size(of: caches))
        }.value
        storage = (result.0, result.1, result.2)
    }

    nonisolated private static func size(of folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// The app's Caches folder (downloaded artwork and the like); iOS may empty it anyway.
    private func clearCache() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for item in (try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
        URLCache.shared.removeAllCachedResponses()
        LogStore.shared.log("[settings] cache cleared")
        Task { await measureStorage() }
    }

    // MARK: Sheets

    @ViewBuilder private func sheetContent(_ sheet: ConsoleSettingsSheet) -> some View {
        switch sheet {
        case .allSettings: AllSettingsView()
        case .steamSignIn: SteamSignInView()
        case .dock: MadeiraDockView(start: startDock)
        default:
            NavigationStack {
                Form {
                    switch sheet {
                    case .jit: JITSettingsSection()
                    case .display: DisplayRateSettings()
                    case .memory: RuntimeMemorySyncSettings(open: { openSheet($0) }, refresh: refresh)
                    case .steam: SteamSettingsSection(open: { openSheet($0) })
                    case .mono: WineMonoSettingsSection()
                    case .saves: SavesSection()
                    case .credits: MadeiraCreditsSection()
                    case .allSettings, .steamSignIn, .dock: EmptyView()
                    }
                }
                .navigationTitle(sheet.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.sheet = nil } } }
            }
        }
    }

    private func openSheet(_ next: SettingsSheet) {
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

    private func handle(_ command: String) {
        guard active, sheet == nil, !restartNotice, !signOut else { return }
        let all = Category.allCases
        let focusable = items(category).enumerated().filter { $0.element.focusable }.map(\.offset)
        withAnimation(ConsoleHomeView.motion) {
            if let current = row {
                let at = focusable.firstIndex(of: current) ?? 0
                switch command {
                case "up": row = focusable[max(0, at - 1)]
                case "down": row = focusable[min(focusable.count - 1, at + 1)]
                case "left": if !items(category)[current].adjust(-1) { row = nil }
                case "right": _ = items(category)[current].adjust(1)
                case "back": row = nil
                case "accept": items(category)[current].activate()
                default: break
                }
            } else {
                let i = all.firstIndex(of: category) ?? 0
                switch command {
                case "up": category = all[max(0, i - 1)]
                case "down": category = all[min(all.count - 1, i + 1)]
                case "right", "accept": row = focusable.first
                case "back": exit()
                default: break
                }
            }
        }
    }
}

/// A GameHub card: a slightly lighter plate with a hairline edge.
struct GameHubCard: View {
    var cornerRadius: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.045)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Color.white.opacity(0.08)))
    }
}

/// One row of a settings panel.
enum GameHubRow {
    case header(String)
    case toggle(String, String, detail: String? = nil, Binding<Bool>)
    case nav(String, String, detail: String? = nil, value: String? = nil, action: () -> Void)
    case check(String, String, detail: String?, Bool, () -> Void)
    case slider(String, String, Binding<Double>, ClosedRange<Double>, step: Double, format: String)
    case info(String, String, value: String)

    var focusable: Bool { if case .header = self { return false }; if case .info = self { return false }; return true }

    func activate() {
        switch self {
        case .toggle(_, _, _, let value): value.wrappedValue.toggle()
        case .nav(_, _, _, _, let action): action()
        case .check(_, _, _, _, let action): action()
        default: break
        }
    }

    /// Left/right on a slider; false when there is nothing to adjust.
    func adjust(_ step: Int) -> Bool {
        guard case .slider(_, _, let value, let range, let size, _) = self else { return false }
        value.wrappedValue = min(max(value.wrappedValue + Double(step) * size, range.lowerBound), range.upperBound)
        return true
    }
}

/// A panel's rows: consecutive rows share a card, a header starts a new one.
struct GameHubRowGroups: View {
    let items: [GameHubRow]
    let focused: Int?

    private var groups: [(header: String?, rows: [(index: Int, row: GameHubRow)])] {
        var out: [(header: String?, rows: [(index: Int, row: GameHubRow)])] = []
        for (i, item) in items.enumerated() {
            if case .header(let title) = item { out.append((title, [])); continue }
            if out.isEmpty { out.append((nil, [])) }
            out[out.count - 1].rows.append((i, item))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if let header = group.header {
                    Text(header).font(.system(size: 15)).foregroundStyle(.white.opacity(0.75)).padding(.top, 6).padding(.leading, 4)
                }
                if !group.rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { n, entry in
                            GameHubRowView(row: entry.row, focused: focused == entry.index).id("row-\(entry.index)")
                            if n < group.rows.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 22)
                            }
                        }
                    }
                    .background(GameHubCard(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }
}

struct GameHubRowView: View {
    let row: GameHubRow
    let focused: Bool

    var body: some View {
        Group {
            switch row {
            case .header: EmptyView()
            case .toggle(_, let title, let detail, let value):
                line(title, detail) { GameHubToggle(on: value.wrappedValue) }
                    .onTapGesture { value.wrappedValue.toggle() }
            case .nav(_, let title, let detail, let value, let action):
                line(title, detail) {
                    HStack(spacing: 10) {
                        if let value { Text(value).font(.system(size: 15)).foregroundStyle(GameHub.secondary) }
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .onTapGesture(perform: action)
            case .check(_, let title, let detail, let on, let action):
                line(title, detail) {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(on ? 0.8 : 0))
                }
                .onTapGesture(perform: action)
            case .slider(_, let title, let value, let range, _, let format):
                line(title, nil) {
                    HStack(spacing: 12) {
                        Slider(value: value, in: range).frame(width: 180).tint(Color(red: 0.12, green: 0.5, blue: 0.85))
                        Text(String(format: format, value.wrappedValue)).font(.system(size: 14).monospacedDigit())
                            .foregroundStyle(GameHub.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
            case .info(_, let title, let value):
                line(title, nil) { Text(value).font(.system(size: 15)).foregroundStyle(GameHub.secondary).lineLimit(1) }
            }
        }
        .background(focused ? Color.white.opacity(0.08) : .clear)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(focused ? Color.white.opacity(0.6) : .clear, lineWidth: 1.5).padding(3))
    }

    private func line<Trailing: View>(_ title: String, _ detail: String?, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17))
                if let detail { Text(detail).font(.system(size: 12.5)).foregroundStyle(GameHub.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 22).padding(.vertical, detail == nil ? 18 : 15)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }
}

/// GameHub's switch: a blue capsule with a light knob.
struct GameHubToggle: View {
    let on: Bool
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.1, green: 0.5, blue: 0.85), Color(red: 0.06, green: 0.4, blue: 0.75)],
                                                              startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.14)))
            Circle().fill(on ? Color(white: 0.92) : Color(white: 0.6)).frame(width: 22, height: 22).padding(4)
        }
        .frame(width: 54, height: 30)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: on)
        .accessibilityRepresentation { Toggle("", isOn: .constant(on)) }
    }
}
