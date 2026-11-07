// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Glass: finding controllers, their button icons, the controller test page, and
// the pointer that makes the system-styled pages reachable from a controller.

import SwiftUI
import GameController
import CoreHaptics
import WebKit

// MARK: - Which controller

enum GlassPadFamily: Equatable {
    case playStation, xbox, generic
    /// PlayStation shapes on DualSense and DualShock, Xbox letters on everything else that
    /// says it is an Xbox pad, and plain letters otherwise.
    static func of(_ controller: GCController?) -> GlassPadFamily {
        guard let controller else { return .generic }
        if controller.extendedGamepad is GCDualSenseGamepad || controller.extendedGamepad is GCDualShockGamepad { return .playStation }
        if controller.extendedGamepad is GCXboxGamepad { return .xbox }
        let name = (controller.vendorName ?? controller.productCategory).lowercased()
        if name.contains("dualsense") || name.contains("dualshock") { return .playStation }
        if name.contains("xbox") { return .xbox }
        return .generic
    }
}

/// The pads iOS sees, kept up to date.
@MainActor final class GlassPads: ObservableObject {
    static let shared = GlassPads()
    @Published private(set) var pads: [GCController] = []
    @Published private(set) var searching = false
    /// Decides every icon on screen: the pad last used, else the first one.
    var active: GCController? { GCController.current ?? pads.first }
    var family: GlassPadFamily { GlassPadFamily.of(active) }

    private init() {
        refresh()
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCControllerDidBecomeCurrent] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { GlassPads.shared.refresh() }
            }
        }
    }

    func refresh() {
        pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        if !pads.isEmpty, searching { stopSearch() }
    }

    /// Picks up a pad in pairing mode that iOS has met before.
    func search() {
        searching = true
        GCController.startWirelessControllerDiscovery { [weak self] in
            Task { @MainActor in self?.searching = false; self?.refresh() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.stopSearch()
        }
    }

    func stopSearch() {
        guard searching else { return }
        searching = false
        GCController.stopWirelessControllerDiscovery()
    }
}

enum GlassPadButton { case accept, back, action, add, tabLeft, tabRight, menu }

/// One button's icon in the active pad's style.
struct GlassGlyph: View {
    let button: GlassPadButton
    @ObservedObject private var pads = GlassPads.shared

    var body: some View {
        switch button {
        case .tabLeft: shoulder(pads.family == .playStation ? "L1" : "LB")
        case .tabRight: shoulder(pads.family == .playStation ? "R1" : "RB")
        case .menu: shoulder(pads.family == .playStation ? "Options" : "Menu")
        default: face
        }
    }

    private func shoulder(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).padding(.horizontal, 5).frame(height: 18)
            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder private var face: some View {
        if pads.family == .playStation {
            Image(systemName: psSymbol).font(.system(size: 9, weight: .heavy)).foregroundStyle(psColor)
                .frame(width: 18, height: 18).background(.white.opacity(0.22), in: Circle())
        } else {
            Text(letter).font(.system(size: 11, weight: .heavy))
                .foregroundStyle(pads.family == .xbox ? xboxColor : .white)
                .frame(width: 18, height: 18).background(.white.opacity(0.22), in: Circle())
        }
    }

    private var psSymbol: String {
        switch button {
        case .accept: return "xmark"
        case .back: return "circle"
        case .action: return "square"
        default: return "triangle"
        }
    }
    private var psColor: Color {
        switch button {
        case .accept: return Color(red: 0.55, green: 0.7, blue: 1)
        case .back: return Color(red: 1, green: 0.5, blue: 0.5)
        case .action: return Color(red: 1, green: 0.6, blue: 0.85)
        default: return Color(red: 0.45, green: 0.9, blue: 0.75)
        }
    }
    private var letter: String {
        switch button {
        case .accept: return "A"
        case .back: return "B"
        case .action: return "X"
        default: return "Y"
        }
    }
    private var xboxColor: Color {
        switch button {
        case .accept: return Color(red: 0.45, green: 0.9, blue: 0.4)
        case .back: return Color(red: 1, green: 0.42, blue: 0.4)
        case .action: return Color(red: 0.45, green: 0.65, blue: 1)
        default: return Color(red: 1, green: 0.85, blue: 0.3)
        }
    }
}

/// The hints along the bottom, only while a controller is around.
struct GlassHints: View {
    var items: [(GlassPadButton, String)]
    @ObservedObject private var pads = GlassPads.shared
    var body: some View {
        if !pads.pads.isEmpty {
            HStack(spacing: 12) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(spacing: 5) {
                        GlassGlyph(button: items[index].0)
                        Text(items[index].1).font(.system(size: 11, weight: .medium))
                    }
                }
            }
            .padding(.horizontal, 12).frame(height: 28)
            .glassSurface(radius: 14)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Controller output tests

/// Rumble through CoreHaptics on the pad's own motors.
@MainActor final class GlassRumble {
    private var engines: [CHHapticEngine] = []
    private var players: [CHHapticPatternPlayer] = []

    func play(on controller: GCController?, where locality: GCHapticsLocality, sharpness: Float, seconds: TimeInterval = 0.8) {
        stop()
        guard let haptics = controller?.haptics, let engine = haptics.createEngine(withLocality: locality) else { return }
        do {
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ], relativeTime: 0, duration: seconds)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            engines = [engine]; players = [player]
        } catch {
            LogStore.shared.log("[glass-pad] rumble test failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        players.forEach { try? $0.stop(atTime: CHHapticTimeImmediate) }
        engines.forEach { $0.stop(completionHandler: nil) }
        players = []; engines = []
    }
}

enum GlassTriggerEffect: String, CaseIterable, Identifiable {
    case off = "Off", resistance = "Resistance", weapon = "Weapon", vibration = "Vibration"
    var id: String { rawValue }

    func apply(to trigger: GCDualSenseAdaptiveTrigger) {
        switch self {
        case .off: trigger.setModeOff()
        case .resistance: trigger.setModeFeedbackWithStartPosition(0.15, resistiveStrength: 0.9)
        case .weapon: trigger.setModeWeaponWithStartPosition(0.3, endPosition: 0.6, resistiveStrength: 1)
        case .vibration: trigger.setModeVibrationWithStartPosition(0.1, amplitude: 0.9, frequency: 0.4)
        }
    }
}

/// A sample of the pad for the test page.
struct GlassPadReading: Equatable {
    var pressed = Set<String>()
    var left = CGPoint.zero, right = CGPoint.zero
    var leftTrigger: Float = 0, rightTrigger: Float = 0
}

struct GlassControllerTest: View {
    var close: () -> Void
    @ObservedObject private var pads = GlassPads.shared
    @State private var reading = GlassPadReading()
    @State private var rumble = GlassRumble()
    @State private var effect = GlassTriggerEffect.off
    @State private var focus = 0
    @State private var backHeld: Date?
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    private var pad: GCController? { pads.active }
    private var dualSense: GCDualSenseGamepad? { pad?.extendedGamepad as? GCDualSenseGamepad }
    private var family: GlassPadFamily { pads.family }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Test controller").font(.system(size: 18, weight: .bold))
                    Text(padLine).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: close).buttonStyle(GlassButtonStyle()).frame(height: 44)
            }
            HStack(spacing: 12) {
                stick("Left stick", reading.left, "l3")
                VStack(spacing: 8) {
                    triggers
                    buttonGrid
                }.frame(maxWidth: .infinity)
                stick("Right stick", reading.right, "r3")
            }
            outputs
            Text(family == .playStation ? "Hold ○ for a second to leave" : "Hold B for a second to leave")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(16)
        .glassSurface(radius: 28)
        .frame(maxWidth: 720)
        .onReceive(timer) { _ in tick() }
        .onDisappear { finish() }
        .onReceive(LibraryController.shared.commands) { handle($0) }
    }

    private var padLine: String {
        guard let pad else { return "No controller connected" }
        var parts = [pad.vendorName ?? pad.productCategory]
        if let battery = pad.battery { parts.append("Battery \(Int(battery.batteryLevel * 100))%") }
        return parts.joined(separator: " · ")
    }

    private func stick(_ name: String, _ point: CGPoint, _ click: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 2)
                Circle().fill(reading.pressed.contains(click) ? Color.accentColor : .white)
                    .frame(width: 22, height: 22).offset(x: point.x * 34, y: -point.y * 34)
            }.frame(width: 92, height: 92)
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var triggers: some View {
        HStack(spacing: 10) {
            bar(family == .playStation ? "L2" : "LT", reading.leftTrigger)
            bar(family == .playStation ? "R2" : "RT", reading.rightTrigger)
        }
    }
    private func bar(_ name: String, _ value: Float) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 11, weight: .bold)).frame(width: 20)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white).frame(width: geo.size.width * CGFloat(value))
                }
            }.frame(height: 8)
        }
    }

    private var buttonNames: [(key: String, label: String)] {
        let ps = family == .playStation
        return [("a", ps ? "✕" : "A"), ("b", ps ? "○" : "B"), ("x", ps ? "□" : "X"), ("y", ps ? "△" : "Y"),
                ("lb", ps ? "L1" : "LB"), ("rb", ps ? "R1" : "RB"), ("up", "↑"), ("down", "↓"), ("left", "←"), ("right", "→"),
                ("menu", ps ? "Opt" : "Menu"), ("view", ps ? "Create" : "View"), ("home", ps ? "PS" : "Home"), ("pad", "Pad")]
    }
    private var buttonGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(buttonNames, id: \.key) { button in
                let on = reading.pressed.contains(button.key)
                Text(button.label).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(on ? .black : .white).frame(maxWidth: .infinity).frame(height: 26)
                    .background(on ? Color.white : .white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var outputActions: [(String, () -> Void)] {
        var list: [(String, () -> Void)] = [
            ("Left motor", { rumble.play(on: pad, where: .leftHandle, sharpness: 0.2) }),
            ("Right motor", { rumble.play(on: pad, where: .rightHandle, sharpness: 0.9) }),
            ("Both", { rumble.play(on: pad, where: .handles, sharpness: 0.5) })
        ]
        if dualSense != nil {
            for option in GlassTriggerEffect.allCases {
                list.append((option.rawValue, { setEffect(option) }))
            }
        }
        return list
    }

    private var outputs: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(outputActions.indices, id: \.self) { index in
                    let name = outputActions[index].0
                    Button(name) { outputActions[index].1() }
                        .buttonStyle(GlassButtonStyle(compact: true, selected: name == effect.rawValue && dualSense != nil && index >= 3))
                        .overlay { if index == focus { GlassFocusRing(radius: 20) } }
                }
            }
            if pad != nil, pad?.haptics == nil {
                Text("This controller doesn't offer rumble to apps on iOS.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if dualSense == nil, pad != nil {
                Text("Adaptive triggers need a DualSense.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func setEffect(_ option: GlassTriggerEffect) {
        effect = option
        guard let dualSense else { return }
        option.apply(to: dualSense.leftTrigger)
        option.apply(to: dualSense.rightTrigger)
    }

    private func handle(_ command: String) {
        switch command {
        case "left": focus = max(0, focus - 1)
        case "right": focus = min(outputActions.count - 1, focus + 1)
        case "accept": if outputActions.indices.contains(focus) { outputActions[focus].1() }
        default: break
        }
    }

    private func tick() {
        guard let pad = pad?.extendedGamepad else { reading = GlassPadReading(); return }
        var next = GlassPadReading()
        let buttons: [(String, GCControllerButtonInput?)] = [
            ("a", pad.buttonA), ("b", pad.buttonB), ("x", pad.buttonX), ("y", pad.buttonY),
            ("lb", pad.leftShoulder), ("rb", pad.rightShoulder),
            ("up", pad.dpad.up), ("down", pad.dpad.down), ("left", pad.dpad.left), ("right", pad.dpad.right),
            ("menu", pad.buttonMenu), ("view", pad.buttonOptions), ("home", pad.buttonHome),
            ("l3", pad.leftThumbstickButton), ("r3", pad.rightThumbstickButton),
            ("pad", (pad as? GCDualSenseGamepad)?.touchpadButton ?? (pad as? GCDualShockGamepad)?.touchpadButton)
        ]
        for (name, button) in buttons where button?.isPressed == true { next.pressed.insert(name) }
        next.left = CGPoint(x: CGFloat(pad.leftThumbstick.xAxis.value), y: CGFloat(pad.leftThumbstick.yAxis.value))
        next.right = CGPoint(x: CGFloat(pad.rightThumbstick.xAxis.value), y: CGFloat(pad.rightThumbstick.yAxis.value))
        next.leftTrigger = pad.leftTrigger.value
        next.rightTrigger = pad.rightTrigger.value
        reading = next
        if pad.buttonB.isPressed {
            if let backHeld { if Date().timeIntervalSince(backHeld) > 1 { self.backHeld = nil; close() } } else { backHeld = Date() }
        } else { backHeld = nil }
    }

    private func finish() {
        rumble.stop()
        if let dualSense { dualSense.leftTrigger.setModeOff(); dualSense.rightTrigger.setModeOff() }
    }
}

// MARK: - The pointer

/// Sign-in, the game settings pages, the store's web pages and the other system-styled
/// screens have no focus system a controller can drive. This pointer does it for all of
/// them at once: the left stick moves it, the accept button presses what is under it, the
/// D-pad scrolls, and the back button closes. Native controls are pressed through their
/// accessibility action, web pages through a click in the page.
@MainActor final class GlassPointer {
    static let shared = GlassPointer()
    private var window: UIWindow?
    private var dot: UIView?
    private var link: CADisplayLink?
    private var position = CGPoint(x: 200, y: 180)
    private var subscription: AnyObject?
    private var clients = 0
    /// Closes whatever the pointer is over: the sheet that asked for it.
    var onBack: (() -> Void)?

    func acquire() {
        clients += 1
        guard clients == 1, !GCController.controllers().isEmpty,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let overlay = PassThroughWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        overlay.rootViewController = root
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        dot.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        dot.layer.cornerRadius = 11
        dot.layer.borderColor = UIColor.black.withAlphaComponent(0.5).cgColor
        dot.layer.borderWidth = 2
        root.view.addSubview(dot)
        overlay.isHidden = false
        window = overlay
        self.dot = dot
        position = CGPoint(x: scene.screen.bounds.midX, y: scene.screen.bounds.midY)
        LibraryController.shared.setPointerMode(true)
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
        subscription = LibraryController.shared.commands.sink { [weak self] in self?.command($0) } as AnyObject
    }

    func release() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        LibraryController.shared.setPointerMode(false)
        link?.invalidate(); link = nil
        window?.isHidden = true; window = nil; dot = nil
        subscription = nil
    }

    @objc private func step() {
        let stick = LibraryController.shared.stickValue
        let size = window?.bounds.size ?? .zero
        func speed(_ v: Float) -> CGFloat {
            let magnitude = abs(v)
            guard magnitude > 0.12 else { return 0 }
            return CGFloat(v) * CGFloat(magnitude) * 13
        }
        position.x = min(max(0, position.x + speed(stick.x)), size.width)
        position.y = min(max(0, position.y - speed(stick.y)), size.height)
        dot?.center = position
    }

    private func targetWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter { !$0.isHidden && !($0 is PassThroughWindow) }.max { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
    }

    private func hit() -> UIView? {
        guard let window = targetWindow() else { return nil }
        return window.hitTest(window.convert(position, from: nil), with: nil)
    }

    private func command(_ name: String) {
        if GlassKeyboardModel.isOpen, name != "add" { return }
        switch name {
        case "accept": press()
        case "back": onBack?()
        case "up": scroll(by: -120)
        case "down": scroll(by: 120)
        case "add": toggleKeyboard()
        default: break
        }
    }

    private func press() {
        guard let view = hit() else { return }
        var ancestor: UIView? = view
        while let current = ancestor {
            if let web = current as? WKWebView { click(in: web); return }
            ancestor = current.superview
        }
        if let element = accessibilityElement(at: position, in: targetWindow()) {
            _ = element.accessibilityActivate()
            return
        }
        (view as? UIControl)?.sendActions(for: .touchUpInside)
    }

    /// The smallest accessibility element under the point.
    private func accessibilityElement(at point: CGPoint, in root: NSObject?) -> NSObject? {
        guard let root else { return nil }
        var best: NSObject?
        var bestArea = CGFloat.greatestFiniteMagnitude
        func visit(_ object: NSObject, _ depth: Int) {
            guard depth < 40 else { return }
            let frame = object.accessibilityFrame
            if object.isAccessibilityElement, frame.contains(point), frame.width * frame.height < bestArea {
                best = object; bestArea = frame.width * frame.height
            }
            if let elements = object.accessibilityElements as? [NSObject] {
                elements.forEach { visit($0, depth + 1) }
            } else if object.accessibilityElementCount() != NSNotFound, object.accessibilityElementCount() > 0 {
                for index in 0..<object.accessibilityElementCount() {
                    if let child = object.accessibilityElement(at: index) as? NSObject { visit(child, depth + 1) }
                }
            }
            if let view = object as? UIView { view.subviews.forEach { visit($0, depth + 1) } }
        }
        visit(root, 0)
        return best
    }

    private func click(in web: WKWebView) {
        let local = web.convert(position, from: nil)
        let script = """
        (function(x,y){var e=document.elementFromPoint(x,y);if(!e)return;
        ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(t){
        e.dispatchEvent(new MouseEvent(t,{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y}));});
        if(e.focus)e.focus();})(\(local.x),\(local.y));
        """
        web.evaluateJavaScript(script, completionHandler: nil)
    }

    private func scroll(by amount: CGFloat) {
        var view = hit()
        while let current = view {
            if let web = current as? WKWebView {
                web.evaluateJavaScript("window.scrollBy(0,\(amount))", completionHandler: nil); return
            }
            if let scroller = current as? UIScrollView, scroller.isScrollEnabled, scroller.contentSize.height > scroller.bounds.height {
                let top = -scroller.adjustedContentInset.top
                let bottom = max(top, scroller.contentSize.height - scroller.bounds.height + scroller.adjustedContentInset.bottom)
                let y = min(max(top, scroller.contentOffset.y + amount), bottom)
                scroller.setContentOffset(CGPoint(x: scroller.contentOffset.x, y: y), animated: true)
                return
            }
            view = current.superview
        }
    }

    /// The system keyboard takes text from an attached keyboard or touch; there is nothing
    /// for a pad to press on it, so typing goes through the Glass keyboard.
    private func toggleKeyboard() {
        NotificationCenter.default.post(name: GlassKeyboardModel.toggle, object: nil)
    }
}

private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Added to a system-styled sheet: the pointer runs while it is on screen.
struct GlassPointerHost: ViewModifier {
    var back: () -> Void
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) { GlassKeyboard() }
            .onAppear { GlassPointer.shared.acquire(); GlassPointer.shared.onBack = back }
            .onDisappear { GlassPointer.shared.release() }
    }
}
extension View {
    func glassPointer(back: @escaping () -> Void) -> some View { modifier(GlassPointerHost(back: back)) }
}

// MARK: - Controller keyboard

@MainActor final class GlassKeyboardModel: ObservableObject {
    static let toggle = Notification.Name("GlassKeyboardToggle")
    /// While it is up the pad types, so the pointer leaves its buttons alone.
    static var isOpen = false
    @Published var open = false { didSet { Self.isOpen = open } }
}

/// Types into whatever has the focus, with the pad: the D-pad moves, accept types.
struct GlassKeyboard: View {
    @StateObject private var model = GlassKeyboardModel()
    @State private var row = 1
    @State private var column = 0
    @State private var upper = false
    private let rows: [[String]] = [
        Array("1234567890").map(String.init), Array("qwertyuiop").map(String.init),
        Array("asdfghjkl@").map(String.init), Array("zxcvbnm.-_").map(String.init),
        ["⇧", "Space", "⌫", "Done"]
    ]

    var body: some View {
        Group {
            if model.open {
                VStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 4) {
                            ForEach(rows[r].indices, id: \.self) { c in
                                Text(label(rows[r][c])).font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .foregroundStyle(r == row && c == column ? .black : .white)
                                    .background(r == row && c == column ? Color.white : .white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                            }
                        }
                    }
                }
                .padding(8).glassSurface(radius: 18).padding(.horizontal, 60).padding(.bottom, 6)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: GlassKeyboardModel.toggle)) { _ in model.open.toggle() }
        .onReceive(LibraryController.shared.commands) { handle($0) }
    }

    private func label(_ key: String) -> String { upper && key.count == 1 ? key.uppercased() : key }

    private func handle(_ command: String) {
        guard model.open else { return }
        switch command {
        case "left": column = max(0, column - 1)
        case "right": column = min(rows[row].count - 1, column + 1)
        case "up": row = max(0, row - 1); column = min(column, rows[row].count - 1)
        case "down": row = min(rows.count - 1, row + 1); column = min(column, rows[row].count - 1)
        case "accept": press(rows[row][column])
        case "back": model.open = false
        default: break
        }
    }

    private func press(_ key: String) {
        switch key {
        case "⇧": upper.toggle()
        case "Done": model.open = false
        case "⌫": GlassText.deleteBackward()
        case "Space": GlassText.insert(" ")
        default: GlassText.insert(upper ? key.uppercased() : key); upper = false
        }
    }
}

/// Text into the first responder, or into the field focused in a web page.
enum GlassText {
    @MainActor private static func responder() -> UIResponder? {
        var found: UIResponder?
        let finder = FirstResponderFinder { found = $0 }
        UIApplication.shared.sendAction(#selector(UIResponder.glassReportFirstResponder(_:)), to: nil, from: finder, for: nil)
        return found
    }
    @MainActor private static func web() -> WKWebView? {
        var view = responder() as? UIView
        while let current = view {
            if let web = current as? WKWebView { return web }
            view = current.superview
        }
        return nil
    }
    @MainActor static func insert(_ text: String) {
        if let web = web() {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            web.evaluateJavaScript("document.execCommand('insertText',false,'\(escaped)')", completionHandler: nil)
        } else { (responder() as? UIKeyInput)?.insertText(text) }
    }
    @MainActor static func deleteBackward() {
        if let web = web() { web.evaluateJavaScript("document.execCommand('delete')", completionHandler: nil) }
        else { (responder() as? UIKeyInput)?.deleteBackward() }
    }
}

final class FirstResponderFinder: NSObject {
    let report: (UIResponder) -> Void
    init(_ report: @escaping (UIResponder) -> Void) { self.report = report }
}
extension UIResponder {
    @objc func glassReportFirstResponder(_ sender: Any?) { (sender as? FirstResponderFinder)?.report(self) }
}
