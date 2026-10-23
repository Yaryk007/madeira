// SPDX-License-Identifier: GPL-3.0-or-later
// GameHub: performance modes (Lite, Balanced, Overclock) and paging.

import Foundation

/// How hard GameHub drives the device. iOS gives apps no clock control, so
/// Overclock means every power saving off: guest threads at full priority,
/// the display held at its top refresh rate, a larger JIT pool, lean runtime
/// diagnostics and faster Wine-server requests, and games on the default
/// 60 FPS limit run at the display's maximum. It runs hotter and drains the
/// battery faster. Lite is for devices with little memory: a smaller JIT pool
/// and video memory, paging on, the Dock's compact pool and a 30 FPS default.
/// Balanced leaves madeira.cfg as it was.
enum PerformanceMode: String, CaseIterable, Identifiable {
    case lite, balanced, overclock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lite: return "Lite"
        case .balanced: return "Balanced"
        case .overclock: return "Overclock"
        }
    }
    var detail: String {
        switch self {
        case .lite: return "For devices with 4 GB of memory or less: less memory, paging on, 30 FPS by default."
        case .balanced: return "GameHub's standard settings."
        case .overclock: return "Everything at full speed: no power saving, top refresh rate, a larger JIT pool. More heat, less battery."
        }
    }
}

enum GameHubPerformance {
    static let modeKey = "gamehubPerformanceMode"
    /// madeira.cfg values the keys had before a mode other than Balanced
    /// changed them, put back when Balanced is chosen again.
    static let savedKey = "gamehubPerformanceSaved"

    /// The device's memory in GB (iOS rounds a little under the marketed size).
    static var memoryGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }
    /// 4 GB devices (memory reads about 3.6 GB) get Lite until the user chooses.
    static var lowMemory: Bool { memoryGB < 4.6 }

    static var mode: PerformanceMode {
        if let raw = UserDefaults.standard.string(forKey: modeKey), let mode = PerformanceMode(rawValue: raw) { return mode }
        return lowMemory ? .lite : .balanced
    }

    /// Every madeira.cfg key a mode can set.
    static let keys = ["eco", "pool", "vram-mb", "swap-mb", "env.MADEIRA_PROMOTE", "env.MADEIRA_LEAN_DIAG",
                       "env.MADEIRA_SRV_DIRECT", "env.MADEIRA_ECO_NATIVE", "env.MADEIRA_DOCK_COMPACT_POOL"]

    /// A mode's values; nil removes the key (its default).
    static func values(_ mode: PerformanceMode) -> [String: String?] {
        switch mode {
        case .balanced:
            return [:]
        case .overclock:
            // 1152 MB of JIT pool (the most) where there is room for it; 1024 under 6 GB.
            return ["eco": nil, "pool": memoryGB >= 5.5 ? "1152" : "1024", "env.MADEIRA_PROMOTE": "1", "env.MADEIRA_LEAN_DIAG": "1",
                    "env.MADEIRA_SRV_DIRECT": "1", "env.MADEIRA_ECO_NATIVE": nil, "env.MADEIRA_DOCK_COMPACT_POOL": nil,
                    // The larger pool and full-speed games use more memory: paging backs it
                    // on devices under 8 GB unless paging is already set larger.
                    "swap-mb": memoryGB < 7.5 ? String(max(2048, current("swap-mb"))) : nil]
        case .lite:
            return ["eco": nil, "pool": "640", "vram-mb": "1024", "swap-mb": String(max(2048, current("swap-mb"))),
                    "env.MADEIRA_PROMOTE": nil, "env.MADEIRA_LEAN_DIAG": "1", "env.MADEIRA_SRV_DIRECT": nil,
                    "env.MADEIRA_ECO_NATIVE": "1", "env.MADEIRA_DOCK_COMPACT_POOL": "1"]
        }
    }

    private static func current(_ key: String) -> Int { Int(MadeiraConfig.get(key) ?? "") ?? 0 }

    /// Writes a mode into madeira.cfg. Leaving Balanced remembers the keys'
    /// values first; going back to Balanced puts them back. Read at the next
    /// game start (the JIT pool and paging at the next app start).
    static func apply(_ new: PerformanceMode) {
        let old = mode
        let defaults = UserDefaults.standard
        if old == .balanced && new != .balanced {
            var saved: [String: String] = [:]
            for key in keys { if let value = MadeiraConfig.get(key) { saved[key] = value } }
            defaults.set(saved, forKey: savedKey)
        }
        if new == .balanced {
            let saved = defaults.dictionary(forKey: savedKey) as? [String: String] ?? [:]
            for key in keys { _ = MadeiraConfig.set(key, saved[key]) }
            defaults.removeObject(forKey: savedKey)
        } else {
            for (key, value) in values(new) { _ = MadeiraConfig.set(key, value) }
        }
        defaults.set(new.rawValue, forKey: modeKey)
        LogStore.shared.log("[performance] mode \(old.rawValue) -> \(new.rawValue) memory=\(String(format: "%.1f", memoryGB))GB")
    }

    /// First start on a low-memory device: Lite is written once, as if chosen.
    static func applyRecommendedIfNeeded() {
        guard UserDefaults.standard.string(forKey: modeKey) == nil else { return }
        if lowMemory {
            UserDefaults.standard.set(PerformanceMode.balanced.rawValue, forKey: modeKey)
            apply(.lite)
        } else {
            UserDefaults.standard.set(PerformanceMode.balanced.rawValue, forKey: modeKey)
        }
    }

    /// A game's FPS limit as the mode runs it: the default 60 becomes the
    /// display maximum in Overclock and 30 in Lite (where the device caps at 30).
    /// A limit the player chose for the game is kept.
    static func fps(_ mode: Int) -> Int {
        guard mode == 1 else { return mode }
        switch self.mode {
        case .overclock: return 0
        case .lite: return ProMotionIntent.has30Cap ? 3 : 1
        case .balanced: return 1
        }
    }

    // MARK: Paging

    /// Paging's sizes in MB (the swap tier's file); 0 is off.
    static let pagingChoices = [0, 1024, 2048, 3072, 4096]
    static var paging: Int { current("swap-mb") }
    static func setPaging(_ mb: Int) {
        _ = MadeiraConfig.set("swap-mb", mb > 0 ? String(mb) : nil)
        LogStore.shared.log("[performance] paging=\(mb)MB")
    }
    static func pagingLabel(_ mb: Int) -> String { mb == 0 ? "Off" : "\(mb / 1024) GB" }

    /// Free storage, which paging's file needs room in.
    static var freeStorageGB: Double {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        return Double(free) / 1_073_741_824
    }
}
