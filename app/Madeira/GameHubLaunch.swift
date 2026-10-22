import SwiftUI
import GameController
import UIKit

/// GamehubiOS's starting screen pieces (Library.swift's launchView), after
/// GameHub's: a dark-blue field, the Windows mark ⇄ the game's icon, a sliding
/// bar, and the connected controller in the top corner. The motion is slow and
/// stops with Reduce Motion.

struct GameHubLaunchBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.035, blue: 0.065)
            RadialGradient(colors: [Color(red: 0.07, green: 0.14, blue: 0.26), .clear], center: .center,
                           startRadius: 0, endRadius: breathe ? 560 : 470)
            RadialGradient(colors: [Color(red: 0.12, green: 0.3, blue: 0.6).opacity(breathe ? 0.22 : 0.12), .clear],
                           center: UnitPoint(x: 0.38, y: 0.45), startRadius: 0, endRadius: 220)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// The four-pane Windows mark, waving as on GameHub's screen.
struct GameHubWindowsMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let gap = s * 0.05
            let pane = (s - gap) / 2
            let fill = LinearGradient(colors: [Color(white: 0.92), Color(white: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                GridRow { RoundedRectangle(cornerRadius: s * 0.03).fill(fill).frame(width: pane, height: pane)
                          RoundedRectangle(cornerRadius: s * 0.03).fill(fill).frame(width: pane, height: pane) }
                GridRow { RoundedRectangle(cornerRadius: s * 0.03).fill(fill).frame(width: pane, height: pane)
                          RoundedRectangle(cornerRadius: s * 0.03).fill(fill).frame(width: pane, height: pane) }
            }
            .rotation3DEffect(.degrees(-18), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotationEffect(.degrees(-4))
            .frame(width: geo.size.width, height: geo.size.height)
            .shadow(color: Color(red: 0.3, green: 0.5, blue: 0.9).opacity(0.35), radius: 18)
        }
        .accessibilityHidden(true)
    }
}

/// ⇄, its arrows lighting in turn.
struct GameHubSwapArrows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.right").opacity(reduceMotion ? 0.8 : phase ? 1 : 0.35)
            Image(systemName: "arrow.left").opacity(reduceMotion ? 0.8 : phase ? 0.35 : 1)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { phase = true }
        }
        .accessibilityHidden(true)
    }
}

/// The game's icon tile: its .exe icon on white when it has one, else its cover.
struct GameHubLaunchIcon: View {
    let entry: LibraryEntry
    var appID: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if let appID {
                    SteamGameArtwork(appID: appID)
                } else if entry.coverFile == nil, let icon = GameArtwork.icon(entry) {
                    Color.white
                    Image(uiImage: icon).resizable().interpolation(.high).scaledToFit().padding(s * 0.12)
                } else {
                    LibraryArtwork(entry: entry)
                }
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: s * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
            .offset(y: float ? -3 : 3)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { float = true }
        }
        .accessibilityLabel(entry.title)
    }
}

/// An indeterminate bar: a blue segment gliding along a dim track.
struct GameHubLaunchBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSince(start)
                // Ease back and forth over 2.4 s.
                let p = (1 - cos((t.truncatingRemainder(dividingBy: 2.4) / 2.4) * 2 * .pi)) / 2
                let segment = geo.size.width * 0.42
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.15, green: 0.5, blue: 1), Color(red: 0.25, green: 0.62, blue: 1)],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: segment)
                        .offset(x: reduceMotion ? geo.size.width * 0.08 : (geo.size.width - segment) * p)
                }
            }
        }
        .accessibilityLabel("Launching")
    }
}

/// "Device connected" and the controller's name, only while a controller is connected.
struct GameHubControllerPill: View {
    @ObservedObject private var pads = GameHubControllers.shared
    var body: some View {
        if let name = pads.name { GameHubPadBadge(title: "Device connected", name: name) }
    }
}

struct GameHubPadBadge: View {
    let title: String
    let name: String
    var connected = true
    /// The PlayStation or Xbox mark for those controllers, by the name iOS gives them.
    private var symbol: String {
        let lower = name.lowercased()
        if lower.contains("dualsense") || lower.contains("dualshock") || lower.contains("playstation") { return "playstation.logo" }
        if lower.contains("xbox") { return "xbox.logo" }
        return "gamecontroller"
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: connected ? symbol : "gamecontroller.slash").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(connected ? Color(red: 0.4, green: 0.6, blue: 1) : Color.white.opacity(0.5))
                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                Text(name).font(.system(size: 14)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            }
        }
        .padding(.leading, 6).padding(.trailing, 18).padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.1).opacity(0.92)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
    }
}

/// The connected game controller, for the status corner, the toast and the
/// starting screen.
@MainActor final class GameHubControllers: ObservableObject {
    static let shared = GameHubControllers()
    @Published private(set) var name: String?
    /// The last connect or disconnect, shown as a toast for a few seconds.
    @Published private(set) var toast: (name: String, connected: Bool, id: UUID)?
    private var observers: [NSObjectProtocol] = []

    private init() {
        name = Self.current()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            let pad = note.object as? GCController
            MainActor.assumeIsolated { self?.changed(pad.map(Self.label), connected: true) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            let pad = note.object as? GCController
            MainActor.assumeIsolated { self?.changed(pad.map(Self.label), connected: false) }
        })
    }

    private func changed(_ label: String?, connected: Bool) {
        name = Self.current()
        let id = UUID()
        toast = (label ?? "Controller", connected, id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.toast?.id == id { self?.toast = nil }
        }
    }

    private static func label(_ pad: GCController) -> String { pad.vendorName ?? "Controller" }
    private static func current() -> String? {
        (GCController.current ?? GCController.controllers().first).map(label)
    }
}
