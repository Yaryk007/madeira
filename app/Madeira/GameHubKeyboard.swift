// SPDX-License-Identifier: GPL-3.0-or-later
// GamehubiOS: the on-screen keyboard, PS5's layout in GameHub's look.

import SwiftUI
import UIKit
@preconcurrency import GameController

/// The keyboard of a library session: a panel along the bottom edge with
/// PS5's key grid (letters, a right-hand action column, a bottom row of
/// modifiers and arrows) drawn in GameHub's dark cards. Keys reach the game as
/// Windows key presses (winios_post_key). A controller types on it as on a
/// console: the D-pad moves the focus, A presses, B closes, X deletes, Y is
/// space, LB/RB the arrow keys, L3 shift, View the symbols page and Start
/// Enter. Its window passes every touch outside the panel to the game.
@MainActor final class GameHubKeyboardModel: ObservableObject {
    static let shared = GameHubKeyboardModel()

    enum Page { case letters, symbols }
    enum Action: Equatable {
        case char(Character, shifted: Character)
        case vk(Int32)
        case shift, page, modifier(Int32), close
    }
    struct Key: Identifiable, Equatable {
        let id: String
        var label: String
        var action: Action
        var width: CGFloat = 1
        var symbol: String? = nil
        var accent = false
        /// The controller button that presses it, shown in its corner.
        var pad: PadHint? = nil
    }
    enum PadHint { case a, b, x, y, lb, rb, l3, view, start }

    @Published var page: Page = .letters
    @Published var shift = false
    @Published var capsLock = false
    @Published var held: Set<Int32> = []
    @Published var focus: (row: Int, col: Int) = (1, 0)
    @Published var focusVisible = false
    /// What was typed lately, for the panel's line (Windows keeps the real text).
    @Published var echo = ""
    private var lastShiftTap = Date.distantPast

    var rows: [[Key]] {
        let letters = page == .letters
        let upper = shift || capsLock
        func chars(_ row: Int, _ base: String, _ shifted: String) -> [Key] {
            zip(base, shifted).enumerated().map { i, pair in
                let show = letters && upper ? pair.1 : pair.0
                return Key(id: "r\(row)c\(i)", label: String(show), action: .char(pair.0, shifted: pair.1))
            }
        }
        var r0: [Key], r1: [Key], r2: [Key], r3: [Key]
        if letters {
            r0 = chars(0, "1234567890", "!@#$%^&*()")
            r1 = chars(1, "qwertyuiop", "QWERTYUIOP")
            r2 = chars(2, "asdfghjkl'", "ASDFGHJKL\"")
            r3 = chars(3, "zxcvbnm,./", "ZXCVBNM<>?")
        } else {
            r0 = chars(0, "!@#$%^&*()", "!@#$%^&*()")
            r1 = chars(1, "-_=+[]{}\\|", "-_=+[]{}\\|")
            r2 = chars(2, ";:'\"`~<>?/", ";:'\"`~<>?/")
            r3 = (0..<10).map { i in Key(id: "r3c\(i)", label: "F\(i + 1)", action: .vk(Int32(0x70 + i))) }
        }
        r0.append(Key(id: "back", label: "", action: .vk(0x08), width: 2, symbol: "delete.left", pad: .x))
        r1.append(Key(id: "esc", label: "Esc", action: .vk(0x1B), width: 2))
        r2.append(Key(id: "enter", label: "Enter", action: .vk(0x0D), width: 2, accent: true, pad: .start))
        r3.append(Key(id: "tab", label: letters ? "Tab" : "F11", action: .vk(letters ? 0x09 : 0x7A), width: 2))
        let r4: [Key] = [
            Key(id: "shift", label: "", action: .shift, width: 1.5, symbol: capsLock ? "capslock.fill" : shift ? "shift.fill" : "shift", pad: .l3),
            Key(id: "page", label: letters ? "&123" : "ABC", action: .page, width: 1.5, pad: .view),
            Key(id: "ctrl", label: "Ctrl", action: .modifier(0x11)),
            Key(id: "alt", label: "Alt", action: .modifier(0x12)),
            Key(id: "space", label: "Space", action: .vk(0x20), width: 3, pad: .y),
            Key(id: "left", label: "", action: .vk(0x25), symbol: "arrow.left", pad: .lb),
            Key(id: "up", label: "", action: .vk(0x26), symbol: "arrow.up"),
            Key(id: "down", label: "", action: .vk(0x28), symbol: "arrow.down"),
            Key(id: "right", label: "", action: .vk(0x27), symbol: "arrow.right", pad: .rb),
        ]
        return [r0, r1, r2, r3, r4]
    }

    func press(_ key: Key) {
        if GameHubPrefs.buttonHaptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        switch key.action {
        case .char(let base, let shifted):
            let ch = page == .letters && (shift || capsLock) ? shifted : base
            type(ch)
            if shift && !capsLock { shift = false }
        case .vk(let vk):
            tap(vk)
            switch vk {
            case 0x08: if !echo.isEmpty { echo.removeLast() }
            case 0x20: echo.append(" ")
            case 0x0D: echo = ""
            default: break
            }
        case .shift:
            let now = Date()
            if capsLock { capsLock = false; shift = false }
            else if shift && now.timeIntervalSince(lastShiftTap) < 0.4 { capsLock = true }
            else { shift.toggle() }
            lastShiftTap = now
        case .page:
            page = page == .letters ? .symbols : .letters
        case .modifier(let vk):
            if held.contains(vk) { held.remove(vk); winios_post_key(vk, 0) }
            else { held.insert(vk); winios_post_key(vk, 1) }
        case .close:
            LibraryKeyboard.hide()
        }
    }

    private func type(_ ch: Character) {
        guard let (vk, needsShift) = MetalBackedView.vkForChar(ch) else { return }
        let temporary = needsShift && !held.contains(0x10)
        if temporary { winios_post_key(0x10, 1) }
        tap(vk)
        if temporary { winios_post_key(0x10, 0) }
        echo.append(ch)
        if echo.count > 60 { echo.removeFirst(echo.count - 60) }
    }

    /// One key press; Ctrl and Alt let go after it, as sticky modifiers do.
    private func tap(_ vk: Int32) {
        winios_post_key(vk, 1); winios_post_key(vk, 0)
        if !held.isEmpty { releaseModifiers() }
    }

    func releaseModifiers() {
        for vk in held { winios_post_key(vk, 0) }
        held.removeAll()
    }

    func reset() {
        releaseModifiers()
        page = .letters; shift = false; capsLock = false; echo = ""
        focus = (1, 0); focusVisible = GCController.current != nil
    }

    // MARK: Controller

    func handle(_ command: String) {
        let rows = self.rows
        func key(_ id: String) -> Key? { rows.joined().first { $0.id == id } }
        if !focusVisible, ["up", "down", "left", "right"].contains(command) { focusVisible = true; return }
        switch command {
        case "left": focus.col = max(0, focus.col - 1)
        case "right": focus.col = min(rows[focus.row].count - 1, focus.col + 1)
        case "up", "down":
            let target = command == "up" ? focus.row - 1 : focus.row + 1
            guard rows.indices.contains(target) else { return }
            focus = (target, Self.nearest(in: rows[target], to: Self.center(of: focus.col, in: rows[focus.row])))
        case "accept":
            focusVisible = true
            let row = rows[focus.row]
            press(row[min(focus.col, row.count - 1)])
        case "back": LibraryKeyboard.hide()
        case "x": key("back").map(press)
        case "add": key("space").map(press)
        case "tabPrev": key("left").map(press)
        case "tab": key("right").map(press)
        case "l3": key("shift").map(press)
        case "view": key("page").map(press)
        case "menu": key("enter").map(press)
        default: break
        }
    }

    private static func center(of col: Int, in row: [Key]) -> CGFloat {
        let before = row.prefix(col).reduce(0) { $0 + $1.width }
        return before + (row.indices.contains(col) ? row[col].width / 2 : 0)
    }
    private static func nearest(in row: [Key], to x: CGFloat) -> Int {
        var best = 0, distance = CGFloat.infinity, start: CGFloat = 0
        for (i, key) in row.enumerated() {
            let d = abs(start + key.width / 2 - x)
            if d < distance { distance = d; best = i }
            start += key.width
        }
        return best
    }
}

struct GameHubKeyboardView: View {
    @ObservedObject private var model = GameHubKeyboardModel.shared
    @ObservedObject private var pads = GameHubControllers.shared
    @State private var caret = true

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 24, 940)
            let height = min(geo.size.height * 0.62, 350)
            let gap: CGFloat = 7
            let keyHeight = max(30, (height - 64 - gap * 4 - 22) / 5)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    header
                    VStack(spacing: gap) {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { r, row in
                            let units = row.reduce(0) { $0 + $1.width }
                            let unit = (width - 36 - gap * CGFloat(row.count - 1)) / units
                            HStack(spacing: gap) {
                                ForEach(Array(row.enumerated()), id: \.element.id) { c, key in
                                    keyView(key, focused: model.focusVisible && model.focus.row == r && model.focus.col == c)
                                        .frame(width: unit * key.width, height: keyHeight)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, max(14, geo.safeAreaInsets.bottom))
                .frame(width: width)
                .background(
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 26, bottomLeading: 0, bottomTrailing: 0, topTrailing: 26), style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.11, blue: 0.125).opacity(0.97), GameHub.background.opacity(0.98)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 26, bottomLeading: 0, bottomTrailing: 0, topTrailing: 26), style: .continuous)
                            .stroke(Color.white.opacity(0.09)))
                        .shadow(color: .black.opacity(0.55), radius: 30, y: -6)
                        .ignoresSafeArea(edges: .bottom)
                )
                .background(GeometryReader { panel in
                    Color.clear.onAppear { LibraryKeyboard.panel = panel.frame(in: .global) }
                        .onChange(of: panel.frame(in: .global)) { _, frame in LibraryKeyboard.panel = frame }
                })
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(edges: .bottom)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onReceive(LibraryController.shared.commands) { model.handle($0) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                caret.toggle()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            GHImage(name: "gh-keyboard", fallback: "keyboard").frame(width: 24, height: 20).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 1) {
                Text(model.echo.isEmpty ? " " : model.echo).font(.system(size: 17)).lineLimit(1).truncationMode(.head)
                Rectangle().fill(GameHub.link).frame(width: 2, height: 20).opacity(caret ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08)))
            Button { LibraryKeyboard.hide() } label: {
                HStack(spacing: 6) {
                    padGlyph(.b)
                    Text("Close").font(.system(size: 15))
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(GameHubCard(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close keyboard")
        }
    }

    private func keyView(_ key: GameHubKeyboardModel.Key, focused: Bool) -> some View {
        let active: Bool = {
            switch key.action {
            case .shift: return model.shift || model.capsLock
            case .modifier(let vk): return model.held.contains(vk)
            case .page: return model.page == .symbols
            default: return false
            }
        }()
        let isCharacter: Bool = { if case .char = key.action { return true }; return false }()
        return Button { model.press(key) } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let symbol = key.symbol { Image(systemName: symbol).font(.system(size: 18, weight: .medium)) }
                    else { Text(key.label).font(.system(size: isCharacter ? 20 : 15, weight: isCharacter ? .regular : .medium)).minimumScaleFactor(0.6) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let pad = key.pad, pads.name != nil { padGlyph(pad).scaleEffect(0.78).padding(4).opacity(focused ? 0.9 : 0.6) }
            }
            .foregroundStyle(focused ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(focused ? AnyShapeStyle(Color.white)
                          : key.accent ? AnyShapeStyle(GameHub.postBlue)
                          : active ? AnyShapeStyle(Color(red: 0.2, green: 0.45, blue: 0.85).opacity(0.55))
                          : AnyShapeStyle(Color.white.opacity(isCharacter ? 0.075 : 0.13)))
            )
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(focused ? 0 : 0.07)))
            .shadow(color: focused ? Color.white.opacity(0.35) : .clear, radius: 10)
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: focused)
            .contentShape(Rectangle())
        }
        .buttonStyle(GameHubKeyPress())
        .accessibilityLabel(key.symbol.map { _ in key.id } ?? key.label)
    }

    /// The controller button in the pad's own style: PlayStation shapes or Xbox letters.
    @ViewBuilder private func padGlyph(_ pad: GameHubKeyboardModel.PadHint) -> some View {
        let sony = (pads.name ?? "").lowercased().contains("dual")
        let text: String = switch pad {
        case .a: sony ? "✕" : "A"
        case .b: sony ? "○" : "B"
        case .x: sony ? "□" : "X"
        case .y: sony ? "△" : "Y"
        case .lb: sony ? "L1" : "LB"
        case .rb: sony ? "R1" : "RB"
        case .l3: "L3"
        case .view: sony ? "Share" : "View"
        case .start: sony ? "Options" : "Menu"
        }
        let round = [.a, .b, .x, .y].contains(pad)
        Text(text).font(.system(size: round ? 11 : 8, weight: .bold))
            .frame(minWidth: 18, minHeight: 18).padding(.horizontal, round ? 0 : 3)
            .background(Group {
                if round { Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.2) }
                else { RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.55), lineWidth: 1.2) }
            })
    }
}

/// A key sinks a little under the finger.
struct GameHubKeyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.93 : 1).brightness(configuration.isPressed ? 0.15 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// The keyboard's window takes touches only on the panel.
final class GameHubKeyboardWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        LibraryKeyboard.panel.contains(point) ? super.hitTest(point, with: event) : nil
    }
}
