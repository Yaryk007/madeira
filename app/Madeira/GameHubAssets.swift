// SPDX-License-Identifier: GPL-3.0-or-later
// GamehubiOS: GameHub's own logo and icons.

import SwiftUI
import UIKit

/// GameHub's images, which tools/gamehub-assets.py takes from the official
/// APK into Assets.xcassets/GameHub at build time (the repository does not
/// carry XiaoJi's artwork). A build without them shows SF Symbols instead.
enum GHAsset {
    @MainActor private static var known: [String: Bool] = [:]
    @MainActor static func has(_ name: String) -> Bool {
        if let hit = known[name] { return hit }
        let hit = UIImage(named: name) != nil
        known[name] = hit
        return hit
    }
}

/// One of GameHub's images, or the SF Symbol `fallback`, fitted to its frame.
struct GHImage: View {
    let name: String
    var fallback: String = "questionmark.square.dashed"
    var body: some View {
        if GHAsset.has(name) {
            Image(name).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: fallback).resizable().scaledToFit()
        }
    }
}

/// GameHub's logo: the hexagon controller mark, the mark with "GameHub", or
/// the splash wordmark. Without the build-time assets, the name in text.
struct GameHubLogo: View {
    enum Kind { case mark, wordmark, splash }
    var kind: Kind = .wordmark
    var body: some View {
        let name: String = switch kind {
        case .mark: "gh-logo-mark"
        case .wordmark: "gh-logo-wordmark"
        case .splash: "gh-logo-splash"
        }
        if GHAsset.has(name) {
            Image(name).resizable().interpolation(.high).scaledToFit().accessibilityLabel("GameHub")
        } else {
            Text(kind == .splash ? "GAMEHUB" : "GameHub")
                .font(.system(size: 64, weight: .semibold, design: .rounded)).tracking(kind == .splash ? 4 : 0)
                .minimumScaleFactor(0.1).lineLimit(1)
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.75, green: 0.8, blue: 0.95)], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// GameHub's start: its logo on black for a moment, once per app run.
struct GameHubSplash: View {
    @MainActor static var shown = false
    @State private var visible = !GameHubSplash.shown
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if visible {
            ZStack {
                Color.black.ignoresSafeArea()
                GameHubLogo(kind: .splash).frame(width: 300, height: 60)
                    .opacity(lit ? 1 : 0)
                    .scaleEffect(lit || reduceMotion ? 1 : 0.94)
            }
            .transition(.opacity)
            .task {
                Self.shown = true
                withAnimation(.easeOut(duration: 0.45)) { lit = true }
                try? await Task.sleep(for: .seconds(1.3))
                withAnimation(.easeInOut(duration: 0.35)) { visible = false }
            }
        }
    }
}
