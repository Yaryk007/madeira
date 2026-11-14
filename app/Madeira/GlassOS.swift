// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Glass: the console shell of the design prototype (docs/design/madeira-prototype.dc.html,
// claude.ai/artifact/KQEkAdxryJofnFuXS962PL). Its motion curves played exactly, the boot screen,
// "Who's playing?", the status cluster, the hint bar, switches and segmented controls.

import SwiftUI
import GameController

// MARK: - Look

enum GlassOS {
    /// The prototype's accent, #3B9DFF.
    static let accent = Color(red: 59 / 255, green: 157 / 255, blue: 1)
    /// Text on white: #101014.
    static let ink = Color(red: 16 / 255, green: 16 / 255, blue: 20 / 255)
    /// The page colour under everything: #08080B.
    static let night = Color(red: 8 / 255, green: 8 / 255, blue: 11 / 255)

    static let bootKey = "madeiraGlassBootAnimation"
    static let askProfileKey = "madeiraGlassAskProfile"
    /// Settings › Appearance › Startup animation.
    static var bootAnimation: Bool { UserDefaults.standard.object(forKey: bootKey) as? Bool ?? true }
    /// Settings › Appearance › Ask who's playing.
    static var askProfile: Bool { UserDefaults.standard.object(forKey: askProfileKey) as? Bool ?? true }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: - Motion

/// The prototype's curves. `spring` is its CSS `--spring`, a piecewise-linear easing with
/// a small overshoot; `ease` is `--ease`; `open` is the cover's growth into the game.
enum GlassMotion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
    static func spring(_ duration: Double) -> Animation {
        reduced ? .easeOut(duration: 0.15) : Animation(GlassSpringCurve(duration: duration))
    }
    /// cubic-bezier(0.16, 1, 0.3, 1)
    static func ease(_ duration: Double) -> Animation {
        reduced ? .easeOut(duration: 0.15) : .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }
    /// cubic-bezier(0.22, 1, 0.36, 1)
    static func open(_ duration: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    /// CSS `ease`: cubic-bezier(0.25, 0.1, 0.25, 1)
    static func css(_ duration: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: duration) }
}

/// CSS linear(0, 0.18 8%, 0.52 18%, 0.82 30%, 1.02 42%, 1.06 52%, 1.04 64%, 1.01 78%, 1).
struct GlassSpringCurve: CustomAnimation {
    var duration: Double
    private static let xs: [Double] = [0, 0.08, 0.18, 0.30, 0.42, 0.52, 0.64, 0.78, 1]
    private static let ys: [Double] = [0, 0.18, 0.52, 0.82, 1.02, 1.06, 1.04, 1.01, 1]

    static func value(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var i = 1
        while i < xs.count - 1 && xs[i] < x { i += 1 }
        let t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
        return ys[i - 1] + (ys[i] - ys[i - 1]) * t
    }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: Self.value(time / duration))
    }
}

/// A CSS cubic-bezier, for motion drawn frame by frame (the boot screen).
struct GlassBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double
    static let ease = GlassBezier(x1: 0.16, y1: 1, x2: 0.3, y2: 1)
    static let css = GlassBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let inOut = GlassBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static let draw = GlassBezier(x1: 0.65, y1: 0, x2: 0.35, y2: 1)

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            let value = Self.sample(t, x1, x2)
            if abs(value - x) < 1e-5 { break }
            if value < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return Self.sample(t, y1, y2)
    }
    private static func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }
}

private func phase(_ t: Double, _ start: Double, _ length: Double) -> Double {
    min(1, max(0, (t - start) / length))
}

// MARK: - Shell state

/// Which part of the console is up. It lives outside GlassRootView so ending a game,
/// which rebuilds the home view, does not play the boot screen again.
@MainActor final class GlassShell: ObservableObject {
    enum Stage { case boot, welcome, home }
    static let shared = GlassShell()
    @Published var stage: Stage
    /// Bumped to replay the boot screen (Quick menu › Power › Restart).
    @Published var bootRun = 0

    private init() {
        stage = GlassOS.bootAnimation && !UIAccessibility.isReduceMotionEnabled ? .boot : (GlassOS.askProfile ? .welcome : .home)
    }

    func bootFinished() {
        withAnimation(GlassMotion.css(0.3)) { stage = GlassOS.askProfile ? .welcome : .home }
    }
    func restart() {
        bootRun += 1
        stage = .boot
    }
    func switchUser() { withAnimation(GlassMotion.css(0.25)) { stage = .welcome } }
    func enter(_ profile: GlassProfile) {
        GlassProfiles.shared.select(profile.id)
        withAnimation(GlassMotion.ease(0.36)) { stage = .home }
    }
}

// MARK: - Profiles

struct GlassProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var colour: Int
    var initial: String { String(name.prefix(1)).uppercased() }
    var color: Color { GlassProfiles.colours[colour % GlassProfiles.colours.count] }
}

/// Who is playing. Local names only: they choose what the console greets, not a store account.
@MainActor final class GlassProfiles: ObservableObject {
    static let shared = GlassProfiles()
    static let colours: [Color] = [GlassOS.accent, Color(red: 0.37, green: 0.36, blue: 0.9),
                                   Color(red: 0.19, green: 0.82, blue: 0.35), Color(red: 1, green: 0.62, blue: 0.04)]
    private let listKey = "madeiraGlassProfiles", currentKey = "madeiraGlassProfile"

    @Published private(set) var list: [GlassProfile]
    @Published private(set) var currentID: String

    private init() {
        if let data = UserDefaults.standard.data(forKey: listKey),
           let saved = try? JSONDecoder().decode([GlassProfile].self, from: data), !saved.isEmpty {
            list = saved
        } else {
            list = [GlassProfile(id: "p1", name: "Player 1", colour: 0), GlassProfile(id: "guest", name: "Guest", colour: 1)]
        }
        currentID = UserDefaults.standard.string(forKey: currentKey) ?? "p1"
    }

    var current: GlassProfile { list.first { $0.id == currentID } ?? list[0] }

    func select(_ id: String) {
        currentID = id
        UserDefaults.standard.set(id, forKey: currentKey)
    }
    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].name = String(trimmed.prefix(16))
        save()
    }
    func add() {
        let n = list.count + 1
        list.append(GlassProfile(id: UUID().uuidString, name: "Player \(n)", colour: list.count))
        save()
    }
    func remove(_ id: String) {
        guard list.count > 1 else { return }
        list.removeAll { $0.id == id }
        if currentID == id { select(list[0].id) }
        save()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: listKey) }
    }
}

struct GlassAvatar: View {
    let profile: GlassProfile
    var size: CGFloat = 32
    var ring = true
    var body: some View {
        Text(profile.initial)
            .font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(profile.color, in: Circle())
            .overlay { if ring { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2).padding(-2) } }
    }
}

// MARK: - Boot

/// The emblem's "M", in the prototype's 76-point box.
private struct GlassEmblemM: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 76
        var p = Path()
        p.move(to: CGPoint(x: 24 * s, y: 52 * s))
        p.addLine(to: CGPoint(x: 24 * s, y: 25 * s))
        p.addLine(to: CGPoint(x: 38 * s, y: 41 * s))
        p.addLine(to: CGPoint(x: 52 * s, y: 25 * s))
        p.addLine(to: CGPoint(x: 52 * s, y: 52 * s))
        return p
    }
}

/// The boot screen: the emblem draws itself, light blooms behind it, the wordmark tracks
/// in and a band of light sweeps it, then everything fades to "Who's playing?". Every value
/// is computed from the time since it appeared, on the prototype's own curves.
struct GlassBootScreen: View {
    var finished: () -> Void
    @State private var start = Date()
    @State private var done = false
    static let length = 2.8

    var body: some View {
        TimelineView(.animation) { context in
            frame(context.date.timeIntervalSince(start))
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Madeira is starting")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Skips the startup animation")
        .task {
            try? await Task.sleep(for: .seconds(Self.length))
            finish()
        }
        .onReceive(LibraryController.shared.commands) { _ in finish() }
    }

    private func finish() {
        guard !done else { return }
        done = true
        finished()
    }

    @ViewBuilder private func frame(_ t: Double) -> some View {
        let out = GlassBezier.css(phase(t, 2.3, 0.5))
        // Glow: 0 → 55% → 100% of 2.4 s, each leg on --ease.
        let g1 = GlassBezier.ease(phase(t, 0, 1.32)), g2 = GlassBezier.ease(phase(t, 1.32, 1.08))
        let glowOpacity = t < 1.32 ? g1 : 1 - 0.25 * g2
        let glowScale = t < 1.32 ? 0.55 + 0.5 * g1 : 1.05 - 0.05 * g2
        let logoScale = 0.92 + 0.08 * GlassBezier.ease(phase(t, 0, 1.32))
        let outline = GlassBezier.draw(phase(t, 0.1, 0.9))
        let letter = GlassBezier.draw(phase(t, 0.55, 0.7))
        let word = GlassBezier.ease(phase(t, 0.6, 1.1))
        let tracking = 20 - 11 * word
        let sweep = GlassBezier.inOut(phase(t, 1.2, 1.4))
        let sub = GlassBezier.css(phase(t, 1.2, 0.8))
        let spin = GlassBezier.css(phase(t, 0.9, 0.4))

        ZStack {
            Color.black
            Circle()
                .fill(RadialGradient(stops: [.init(color: GlassOS.accent.opacity(0.34), location: 0),
                                             .init(color: GlassOS.accent.opacity(0.10), location: 0.38),
                                             .init(color: .clear, location: 0.66)],
                                     center: .center, startRadius: 0, endRadius: 230))
                .frame(width: 460, height: 460)
                .scaleEffect(glowScale).opacity(glowOpacity)
                .offset(y: -20)
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).inset(by: 1.3)
                        .trim(from: 0, to: outline)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 68, height: 68)
                    GlassEmblemM().trim(from: 0, to: letter)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 76, height: 76)
                }
                .frame(width: 76, height: 76)
                .shadow(color: .white.opacity(0.45), radius: 7)
                .scaleEffect(logoScale)
                wordmark(tracking: tracking, sweep: sweep)
                    .opacity(word).blur(radius: 6 * (1 - word))
                    .padding(.top, 22)
                Text("Windows games on iOS")
                    .font(.system(size: 12, weight: .medium)).tracking(0.4)
                    .foregroundStyle(.white.opacity(0.62))
                    .opacity(sub).padding(.top, 8)
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle().stroke(.white.opacity(0.22), lineWidth: 2)
                        .overlay { Circle().trim(from: 0, to: 0.25).stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .butt)) }
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(t / 0.9 * 360))
                        .opacity(spin)
                }
            }
            .padding(.trailing, 45).padding(.bottom, 25)
        }
        .opacity(1 - out)
    }

    /// "MADEIRA" in white at 78%, with the prototype's band of light (a third of the gradient's
    /// 300% width) crossing it from left to right.
    private func wordmark(tracking: Double, sweep: Double) -> some View {
        let text = Text("MADEIRA").font(.system(size: 19, weight: .semibold)).tracking(tracking)
        return text.foregroundStyle(.white.opacity(0.78))
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(colors: [.white.opacity(0), .white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.48)
                        .offset(x: (-0.5 + 2 * sweep) * w - w * 0.24)
                }
                .mask(text)
                .opacity(sweep > 0 && sweep < 1 ? 1 : 0)
            }
            // Tracking trails the last letter too; shift by half so the word stays centred.
            .offset(x: tracking / 2)
    }
}

// MARK: - Clock

struct GlassClock: View {
    var size: CGFloat = 15
    var weight: Font.Weight = .semibold
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: size, weight: weight)).monospacedDigit()
        }
    }
}

struct GlassDateLine: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        }
    }
}

// MARK: - Who's playing?

struct GlassWelcome: View {
    @ObservedObject private var profiles = GlassProfiles.shared
    @ObservedObject private var pads = GlassPads.shared
    @State private var focus = 0
    @State private var shown = false
    var body: some View {
        ZStack {
            Rectangle().fill(GlassOS.night.opacity(0.58)).background(.ultraThinMaterial.opacity(0.6)).ignoresSafeArea()
            VStack(spacing: 0) {
                GlassClock(size: 58, weight: .light).tracking(-1.5).frame(height: 62)
                GlassDateLine().font(.system(size: 15)).foregroundStyle(.white.opacity(0.88)).frame(height: 20)
                Text("Who's playing?").font(.system(size: 15, weight: .semibold)).padding(.top, 26)
                HStack(spacing: 32) {
                    ForEach(Array(profiles.list.enumerated()), id: \.element.id) { index, profile in
                        Button { GlassShell.shared.enter(profile) } label: {
                            VStack(spacing: 10) {
                                GlassAvatar(profile: profile, size: 76, ring: false)
                                    .overlay { if index == focus && !pads.pads.isEmpty { Circle().strokeBorder(.white, lineWidth: 3).padding(-3) } }
                                    .shadow(color: .black.opacity(index == focus ? 0.5 : 0), radius: 15, y: 10)
                                    .scaleEffect(index == focus && !pads.pads.isEmpty ? 1.08 : 1)
                                Text(profile.name).font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .buttonStyle(GlassPressStyle(scale: 0.94))
                        .accessibilityLabel("Play as \(profile.name)")
                    }
                }
                .padding(.top, 14)
                .animation(GlassMotion.spring(0.3), value: focus)
            }
            .foregroundStyle(.white)
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
            VStack {
                Spacer()
                HStack { Spacer(); GlassHintBar(items: [(.accept, "Sign in")]) }
            }
            .padding(.trailing, 44).padding(.bottom, 12)
        }
        .onAppear {
            focus = profiles.list.firstIndex { $0.id == profiles.currentID } ?? 0
            withAnimation(GlassMotion.ease(0.36)) { shown = true }
        }
        .onReceive(LibraryController.shared.commands) { command in
            switch command {
            case "left": focus = max(0, focus - 1)
            case "right": focus = min(profiles.list.count - 1, focus + 1)
            case "accept": if profiles.list.indices.contains(focus) { GlassShell.shared.enter(profiles.list[focus]) }
            default: break
            }
        }
    }
}

// MARK: - Controls

/// Press feedback: the control gives under the finger (the prototype's `:active` scale).
struct GlassPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(GlassMotion.css(0.15), value: configuration.isPressed)
    }
}

/// The prototype's switch: a 56 × 28 track, the knob on its spring.
struct GlassSwitch: View {
    var on: Bool
    var label: String
    var toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: .leading) {
                Capsule().fill(on ? GlassOS.accent : .white.opacity(0.24)).frame(width: 56, height: 28)
                    .animation(GlassMotion.css(0.2), value: on)
                Circle().fill(.white).frame(width: 24, height: 24)
                    .offset(x: on ? 30 : 2)
                    .animation(GlassMotion.spring(0.36), value: on)
            }
            .frame(width: 56, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// The prototype's segmented control: white pill on the chosen option.
struct GlassSegment: View {
    var options: [String]
    var selected: Int
    var glass = false
    var fill = false
    var padding: CGFloat = 15
    var focused = false
    var pick: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let on = index == selected
                Button { pick(index) } label: {
                    Text(options[index]).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(on ? GlassOS.ink : .white.opacity(0.86))
                        .padding(.horizontal, padding).frame(maxWidth: fill ? .infinity : nil).frame(height: 44)
                        .background { if on { Capsule().fill(.white) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(GlassMotion.css(0.18), value: selected)
        .modifier(GlassSegmentBackground(glass: glass))
        .overlay { if focused { GlassFocusRing(radius: 22) } }
    }
}

private struct GlassSegmentBackground: ViewModifier {
    var glass: Bool
    func body(content: Content) -> some View {
        if glass { content.glassSurface(radius: 22) } else { content.background(.white.opacity(0.1), in: Capsule()) }
    }
}

/// A thin progress track (6 points, white fill).
struct GlassTrack: View {
    var value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.12), value: value)
    }
}

/// The controller hints along the bottom right: what each button does on this screen.
struct GlassHintBar: View {
    var items: [(GlassPadButton, String)]
    var body: some View {
        HStack(spacing: 18) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 7) {
                    GlassGlyph(button: items[index].0, size: 22)
                    if !items[index].1.isEmpty { Text(items[index].1).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
                }
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        .frame(height: 24)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A shoulder button's label beside the tab bar (L1/R1 or LB/RB); tapping it steps the tabs.
struct GlassShoulderChip: View {
    let right: Bool
    var action: () -> Void
    @ObservedObject private var pads = GlassPads.shared
    var body: some View {
        Button(action: action) {
            Text(pads.family == .playStation ? (right ? "R1" : "L1") : (right ? "RB" : "LB"))
                .font(.system(size: 11, weight: .bold))
                .frame(width: 32, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .frame(width: 36, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(GlassChipStyle())
        .accessibilityLabel(right ? "Next tab" : "Previous tab")
    }
}

private struct GlassChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? GlassOS.ink : .white.opacity(0.9))
            .background {
                if configuration.isPressed { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white).frame(width: 32, height: 22) }
            }
            .animation(GlassMotion.css(0.15), value: configuration.isPressed)
    }
}

/// A tile of the quick menu.
struct GlassQuickTile: View {
    var label: String
    var value: String
    var focused: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
                Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.white.opacity(focused ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { if focused { GlassFocusRing(radius: 16) } }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(GlassPressStyle())
    }
}

/// The sheet entrance of the prototype (`rise`): fade in from 95% on the spring.
extension AnyTransition {
    static var glassRise: AnyTransition { glassRise(anchor: .center) }
    static func glassRise(anchor: UnitPoint) -> AnyTransition {
        .asymmetric(insertion: .modifier(active: GlassRiseModifier(on: false, anchor: anchor), identity: GlassRiseModifier(on: true, anchor: anchor))
                        .animation(GlassMotion.spring(0.44)),
                    removal: .opacity.animation(GlassMotion.css(0.12)))
    }
    /// A title arriving (`infoin`): up 6 points and in, ease-out 0.3 s.
    static var glassInfo: AnyTransition {
        .asymmetric(insertion: .modifier(active: GlassInfoModifier(on: false), identity: GlassInfoModifier(on: true))
                        .animation(.easeOut(duration: 0.3)),
                    removal: .identity)
    }
    /// The in-game drawer (`slide`): in from 28 points to the left.
    static var glassSlide: AnyTransition {
        .asymmetric(insertion: .modifier(active: GlassSlideModifier(on: false), identity: GlassSlideModifier(on: true))
                        .animation(GlassMotion.spring(0.44)),
                    removal: .opacity.animation(GlassMotion.css(0.12)))
    }
    /// A page arriving (`pagein`): up 8 points and in, on --ease.
    static var glassPage: AnyTransition {
        .asymmetric(insertion: .modifier(active: GlassPageModifier(on: false), identity: GlassPageModifier(on: true))
                        .animation(GlassMotion.ease(0.36)),
                    removal: .identity)
    }
}

private struct GlassRiseModifier: ViewModifier {
    var on: Bool
    var anchor: UnitPoint
    func body(content: Content) -> some View { content.opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.95, anchor: anchor) }
}
private struct GlassInfoModifier: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View { content.opacity(on ? 1 : 0).offset(y: on ? 0 : 6) }
}
private struct GlassSlideModifier: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View { content.opacity(on ? 1 : 0).offset(x: on ? 0 : -28) }
}
private struct GlassPageModifier: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View { content.opacity(on ? 1 : 0).offset(y: on ? 0 : 8) }
}
