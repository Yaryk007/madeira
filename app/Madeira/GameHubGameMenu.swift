// SPDX-License-Identifier: GPL-3.0-or-later
// GamehubiOS: the in-game menu as GameHub draws it.

import SwiftUI
@preconcurrency import GameController

/// GameHub's in-game menu: a dark drawer from the left edge with the game at the
/// top, its tabs under it, the tab's rows in GameHub cards and Exit game at the
/// bottom. It opens from the floating button, Back+Start or a PlayStation
/// controller's touchpad (Settings › Peripherals › Touchpad opens the menu).
/// A controller moves through it as through Settings: LB/RB switch tabs, the
/// D-pad picks a row, A uses it, left/right move a slider, B closes.
struct GameHubGameMenu: View {
    enum Tab: String, CaseIterable, Identifiable {
        case controls, display, pointer, system
        var id: String { rawValue }
        var title: String {
            switch self {
            case .controls: return "Controls"
            case .display: return "Display"
            case .pointer: return "Pointer"
            case .system: return "System"
            }
        }
        var icon: String {
            switch self {
            case .controls: return "gamecontroller"
            case .display: return "display"
            case .pointer: return "cursorarrow.motionlines"
            case .system: return "cpu"
            }
        }
    }

    let openBinds: () -> Void
    @ObservedObject private var model = LibraryModel.shared
    @ObservedObject private var controls = TouchControlsModel.shared
    @ObservedObject private var input = InputSettings.shared
    @ObservedObject private var dockStart = DockStartScreen.shared
    @ObservedObject private var pads = GameHubControllers.shared
    @AppStorage(GameHubPrefs.touchpadMenuKey) private var touchpadMenu = true
    @AppStorage(GameHubPrefs.controllerTypeKey) private var controllerType = "auto"
    @State private var tab: Tab = .controls
    @State private var row: Int?
    /// The developer overlay's ECO and F pills, read each time the menu opens.
    @State private var eco = madeira_get_eco() != 0
    @State private var fenceMode = FPSOverlayFenceMode.current
    private let sessionTools = MadeiraConfig.flag("MADEIRA_SESSION_TOOLS")
    private let sessionDiagnostics = MadeiraConfig.flag("MADEIRA_SESSION_DIAGNOSTICS", fallback: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 18)
            tabBar.padding(.horizontal, 14).padding(.top, 16)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            ScrollViewReader { reader in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        GameHubRowGroups(items: items, focused: row)
                        extras
                    }
                    .padding(16).id(tab)
                }
                .onChange(of: row) { _, value in
                    if let value { withAnimation(ConsoleHomeView.motion) { reader.scrollTo("row-\(value)", anchor: .center) } }
                }
            }
            footer.padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 8)
        }
        .foregroundStyle(.white)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [GameHub.background.opacity(0.97), Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.94)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        )
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).ignoresSafeArea() }
        .environment(\.colorScheme, .dark)
        .onAppear {
            eco = madeira_get_eco() != 0; fenceMode = FPSOverlayFenceMode.current
            // With a controller in hand the focus starts on the first row, as in Settings.
            if GCController.current != nil || pads.name != nil { row = focusable.first }
        }
        .onReceive(LibraryController.shared.commands) { handle($0) }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let appID = dockStart.appID { SteamGameArtwork(appID: appID) }
                else if let entry = model.activeEntry { LibraryArtwork(entry: entry) }
                else { GameHub.tile }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(GameHub.tileStroke))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.activeEntry?.title ?? "Game").font(.system(size: 18, weight: .semibold)).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Playing · \(Self.duration(context.date.timeIntervalSince(model.launchStartedAt)))")
                        .font(.system(size: 13)).foregroundStyle(GameHub.secondary)
                }
            }
            Spacer(minLength: 8)
            Button { model.menu = false } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain).accessibilityLabel("Close menu")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            GameHubShoulderHint(label: "LB")
            ForEach(Tab.allCases) { t in
                let selected = t == tab
                Button { select(t) } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon).font(.system(size: 13, weight: .medium))
                            Text(t.title).font(.system(size: 14, weight: selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Capsule().fill(selected ? Color.white : .clear).frame(width: 18, height: 3)
                    }
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity).padding(.top, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            GameHubShoulderHint(label: "RB")
        }
    }

    /// What a tab shows below its rows.
    @ViewBuilder private var extras: some View {
        switch tab {
        case .controls:
            // The named layouts; this menu replaces the overlay's top bar in a session.
            if controls.visible && ControlPresetsModel.enabled {
                ControlLayoutMenu(style: .row) { openedEditor in
                    model.saveCurrentProfile()
                    if openedEditor { model.menu = false }
                }
                .font(.system(size: 17))
                .padding(.horizontal, 22).frame(minHeight: 62)
                .background(GameHubCard(cornerRadius: 20))
            }
        case .system:
            if let appID = model.activeEntry?.steamAppID, SteamOwnedLibrary.cloudQuitEnabled {
                SteamCloudQuitRow(appID: appID).padding(18).background(GameHubCard(cornerRadius: 20))
            }
        default: EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { model.menu = false } label: {
                Label("Resume", systemImage: "play.fill").font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GameHub.postBlue))
            }
            .buttonStyle(.plain)
            Button { model.requestQuit() } label: {
                Label("Exit game", systemImage: "power").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(GameHubCard(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Closes the running session. Unsaved progress will be lost.")
        }
    }

    // MARK: Rows

    private var items: [GameHubRow] { items(tab) }

    private func items(_ tab: Tab) -> [GameHubRow] {
        switch tab {
        case .controls:
            var list: [GameHubRow] = [.header("Touch controls"),
                .toggle("touch", "Show touch controls", $controls.visible),
                .slider("opacity", "Opacity", $model.opacity, 0.15...1, step: 0.05, format: "%.2f"),
                .slider("size", "Size", Binding(get: { controls.sizeScale }, set: { controls.sizeScale = $0 }), 0.5...2, step: 0.05, format: "%.2f"),
                .nav("edit", "Edit controls") { controls.visible = true; controls.editing = true; model.menu = false },
                .nav("keyboard", "Keyboard") { model.menu = false; LibraryKeyboard.show() },
                .header("Controller")]
            if GamepadInput.keyboardMouseAvailable {
                // The session's resolved mode: nil is the game's own support.
                let current = model.controllerMode ?? "xinput"
                list.append(.nav("mode", "Controller input", detail: current == "dinput" ? "XInput and DirectInput applies at the next launch." : nil,
                                 value: Self.controllerModes.first { $0.0 == current }?.1 ?? "Game's own") {
                    model.controllerMode = LibraryModel.effectiveControllerMode(Self.next(current, in: Self.controllerModes.map(\.0)))
                    model.saveCurrentProfile()
                })
                if model.controllerMode == "keys" {
                    list.append(.nav("binds", "Controller binds") { openBinds() })
                }
            }
            list.append(.nav("type", "Controller type", detail: "How games see your controller. Applies at the next launch.",
                             value: GameHubPrefs.controllerTypes.first { $0.0 == controllerType }?.1 ?? "Auto") {
                controllerType = Self.next(controllerType, in: GameHubPrefs.controllerTypes.map(\.0))
            })
            list.append(.toggle("touchpad", "Touchpad opens this menu", detail: "PS4 and PS5 controllers.", $touchpadMenu))
            return list
        case .display:
            var list: [GameHubRow] = [.header("Frame rate"),
                .nav("fps", "FPS limit", value: Self.fpsModes.first { $0.0 == model.fpsMode }?.1 ?? "60 FPS") {
                    model.setFPS(Self.next(model.fpsMode, in: Self.fpsModes.map(\.0)))
                }]
            if sessionTools {
                list.append(.nav("aspect", "Aspect & scaling", value: model.displayMode.label) {
                    model.displayMode = Self.next(model.displayMode, in: DisplayMode.allCases)
                    model.saveCurrentProfile()
                })
            }
            list.append(.header("Performance overlay"))
            list.append(.toggle("overlay", "Show overlay", $model.performance))
            if model.performance {
                for field in ["FPS", "Frame time", "CPU", "GPU", "RAM", "Battery", "Thermal"] {
                    list.append(.toggle("f-\(field)", field, Binding(get: { model.overlayFields.contains(field) }, set: { on in
                        model.overlayFields.removeAll { $0 == field }; if on { model.overlayFields.append(field) }
                    })))
                }
            }
            return list
        case .pointer:
            let mode = input.touchMode ? 0 : input.relative ? 2 : 1
            let sensitivity = Binding<Double>(get: { input.relative ? input.sensRel : input.sensAbs },
                                              set: { if input.relative { input.sensRel = $0 } else { input.sensAbs = $0 } })
            return [.header("Touch"),
                .check("p-touch", "Touch", detail: "Tap to click where your finger is.", mode == 0, { input.touchMode = true; input.relative = false }),
                .check("p-trackpad", "Trackpad", detail: "Drag the pointer like a trackpad.", mode == 1, { input.touchMode = false; input.relative = false }),
                .check("p-look", "Mouse-look", detail: "Relative movement for 3D cameras.", mode == 2, { input.touchMode = false; input.relative = true }),
                .slider("p-sens", "Sensitivity", sensitivity, 0.1...8, step: 0.1, format: "%.1f")]
        case .system:
            var list: [GameHubRow] = [.header("CPU"),
                .toggle("eco", "Eco mode", detail: "The game's threads on the efficiency cores: cooler and slower. For loading screens.",
                        Binding(get: { eco }, set: { on in eco = on; madeira_set_eco(on ? 1 : 0) }))]
            if sessionTools && sessionDiagnostics {
                list.append(.header("Diagnostics"))
                list.append(.nav("capture", "Capture the next frame", detail: "Direct3D 12. Writes to Documents/capture.") {
                    model.menu = false
                    // After the menu has gone, so the frame shows what the player saw.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        madeira_capture_request(1)
                        LogStore.shared.log("[capture] frame capture requested from the in-game menu")
                    }
                })
                list.append(.nav("fence", "GPU sync", detail: "F1 default, F6 barriers only, F5 fragment stage, F0 none.", value: "F\(fenceMode)") {
                    let mode = Self.next(fenceMode, in: [1, 6, 5, 0])
                    fenceMode = mode; FPSOverlayFenceMode.current = mode
                    madeira_set_fence_mode(Int32(mode == 0 ? 7 : mode))
                })
            }
            return list
        }
    }

    static let controllerModes = [("xinput", "Game's own"), ("dinput", "XInput + DirectInput"), ("keys", "Keyboard & mouse")]
    static var fpsModes: [(Int, String)] {
        var list: [(Int, String)] = []
        if ProMotionIntent.has30Cap { list.append((3, "30 FPS")) }
        if ProMotionIntent.has40Cap { list.append((4, "40 FPS")) }
        return list + [(1, "60 FPS"), (0, "Display max"), (2, "Uncapped")]
    }
    static func next<T: Equatable>(_ value: T, in list: [T]) -> T {
        guard let i = list.firstIndex(of: value) else { return list.first ?? value }
        return list[(i + 1) % list.count]
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    // MARK: Controller

    private var focusable: [Int] { items.enumerated().filter { $0.element.focusable }.map(\.offset) }

    private func select(_ t: Tab) {
        withAnimation(ConsoleHomeView.motion) {
            tab = t
            row = row == nil ? nil : items(t).enumerated().first { $0.element.focusable }?.offset
        }
    }

    private func handle(_ command: String) {
        guard model.menu else { return }
        let tabs = Tab.allCases, at = tabs.firstIndex(of: tab) ?? 0
        let focusable = self.focusable
        withAnimation(ConsoleHomeView.motion) {
            switch command {
            case "tabPrev", "tab":
                let next = tabs[(at + (command == "tab" ? 1 : tabs.count - 1)) % tabs.count]
                tab = next; row = items(next).enumerated().first { $0.element.focusable }?.offset
            case "up", "down":
                guard !focusable.isEmpty else { return }
                guard let current = row, let i = focusable.firstIndex(of: current) else { row = focusable.first; return }
                row = focusable[command == "up" ? max(0, i - 1) : min(focusable.count - 1, i + 1)]
            case "left", "right":
                if let current = row, current < items.count { _ = items[current].adjust(command == "left" ? -1 : 1) }
            case "accept":
                if let current = row, current < items.count { items[current].activate() } else { row = focusable.first }
            default: break
            }
        }
    }
}

/// LB / RB beside the tabs, as GameHub labels its shoulder-button tabs.
struct GameHubShoulderHint: View {
    let label: String
    var body: some View {
        if GHAsset.has(label == "LB" ? "gh-lb" : "gh-rb") {
            GHImage(name: label == "LB" ? "gh-lb" : "gh-rb").frame(width: 24, height: 24).opacity(0.7).accessibilityHidden(true)
        } else {
            drawn
        }
    }
    private var drawn: some View {
        Text(label).font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 28, height: 18)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25)))
            .accessibilityHidden(true)
    }
}
