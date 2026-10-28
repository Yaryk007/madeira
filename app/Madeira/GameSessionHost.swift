// SPDX-License-Identifier: GPL-3.0-or-later
// GameHub: several games in one app run, through a session host.

import Foundation

/// GameHub runs every game in its own iOS process, where a Wine session
/// cannot start twice (the wineserver's objects outlive the first session and
/// init_registry aborts on "\Registry"), so Madeira asked for a restart before
/// a second game. With the host (build/gamehub-host/host.c) as the session's
/// first program, every game is a child process of a session that lasts until
/// GameHub closes: the first game starts Wine with the host and hands it the
/// game as its first job; the next game only writes a new job. Several games
/// can run at once: GameHub's Home leaves the game running (LibraryModel's
/// `running`), another game starts beside it, and the host shows the one in
/// front and minimizes the others' windows.
///
/// Settings read once per app run (the JIT pool, paging, the controller type,
/// the virtual monitor's size) keep the first game's values for later games.
/// Desktop-mode games and Madeira Dock keep their own session and still need
/// a restart after another game.
enum GameSessionHost {
    static let flagKey = "gamehubMultiSession"
    /// Settings › Pause games in the background (on by default): the host suspends them.
    static let pauseKey = "gamehubPauseBackground"
    static var pauseBackground: Bool { UserDefaults.standard.object(forKey: pauseKey) as? Bool ?? true }
    /// Settings › JIT & System › Several games per session (on by default).
    static var enabled: Bool {
        (UserDefaults.standard.object(forKey: flagKey) as? Bool ?? true) && bundled
    }
    static var bundled: Bool {
        Bundle.main.url(forResource: "gamehubhost", withExtension: "exe", subdirectory: "arm64ec-windows") != nil
    }
    static let program = "C:\\windows\\system32\\gamehubhost.exe"

    /// The host's folder, C:\gamehub-host.
    static var folder: URL { LibraryModel.drive.appendingPathComponent("gamehub-host", isDirectory: true) }
    private static var job: URL { folder.appendingPathComponent("job.txt") }
    private static func exited(_ token: Int) -> URL { folder.appendingPathComponent("exited-\(token).txt") }
    nonisolated(unsafe) private static var lastCommand = 0
    nonisolated(unsafe) private static var hostPIDPublished = false
    nonisolated(unsafe) private static var lastBackground = ""
    nonisolated(unsafe) private static var syncTimer: Timer?

    /// The host started this app run (its session is alive while Wine runs).
    nonisolated(unsafe) private(set) static var started = false
    nonisolated(unsafe) private static var lastToken = 0

    /// A session with the host is running, so a game can join it.
    static var alive: Bool { started && wine_process_is_running() != 0 && wineserver_is_running() != 0 }

    /// Games the host can start: a program of its own (not the Wine desktop, not
    /// desktop mode, not a Steam game started through Madeira Dock).
    static func canHost(_ entry: LibraryEntry) -> Bool {
        guard enabled, entry.desktop != true, !entry.runsInDesktop, entry.servicesScript == nil else { return false }
        return entry.steamAppID == nil || entry.startsSteamGameDirectly
    }

    /// Writes the game as the host's next job and returns its token.
    @discardableResult
    static func submit(_ entry: LibraryEntry) -> Int {
        lastToken += 1
        let command = entry.hostCommand
        var lines = ["token=\(lastToken)", "cmd=\(command.line)"]
        lines.append("dir=\(entry.launchDirectory)")
        if entry.startsSteamGameDirectly, let appID = entry.steamAppID {
            lines += ["env=SteamAppId=\(appID)", "env=SteamGameId=\(appID)", "env=SteamAppPath=\(entry.windowsPath)"]
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: exited(lastToken))
        let text = lines.joined(separator: "\n") + "\n"
        // Written whole, then renamed, so the host never reads half a job.
        let partial = folder.appendingPathComponent("job.partial")
        try? text.write(to: partial, atomically: false, encoding: .utf8)
        try? FileManager.default.removeItem(at: job)
        try? FileManager.default.moveItem(at: partial, to: job)
        LogStore.shared.log("[session-host] job \(lastToken): \(entry.title)")
        return lastToken
    }

    /// The first game of the app run: Wine starts the host, the game is its first job.
    static func prepareFirstLaunch(_ entry: LibraryEntry) -> Int {
        try? FileManager.default.removeItem(at: job)
        // The last session's reports and commands mean nothing to this one.
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            where name.hasPrefix("exited") || name.hasPrefix("cmd-") || name == "host-pid.txt" || name == "background.txt" {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        unsetenv("MADEIRA_GAMEHUB_HOST_PID")
        hostPIDPublished = false
        lastBackground = ""
        madeira_set_background_pids(nil, 0)
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in sync() }
        let token = submit(entry)
        setenv("MADEIRA_EXE", program, 1)
        unsetenv("MADEIRA_ARGS")
        unsetenv("MADEIRA_WORKDIR")
        unsetenv("MADEIRA_DESKTOP")
        started = true
        LogStore.shared.log("[session-host] session starts with the host")
        return token
    }

    /// Shows the game's windows and minimizes every other game's (the host's `front`).
    static func front(_ token: Int) { sendPause(); send("front \(token)") }
    /// Minimizes every game's windows while GameHub's home is shown.
    static func hideAll() { sendPause(); send("hide") }

    /// Suspension is only safe once wineserver knows the host (MADEIRA_GAMEHUB_HOST_PID):
    /// a suspend it does not hold for real leaves a thread "suspended" yet running.
    private static func sendPause() {
        sync()
        send("pause \(pauseBackground && hostPIDPublished ? 1 : 0)")
    }

    /// The host's reports: its process id, so wineserver really suspends what it
    /// suspends (mach_ios.c), and the processes of the games behind the front one,
    /// which the audio mixer and the game layer leave out (madeira_set_background_pids).
    static func sync() {
        if !hostPIDPublished,
           let text = try? String(contentsOf: folder.appendingPathComponent("host-pid.txt"), encoding: .utf8),
           let pid = UInt32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid != 0 {
            setenv("MADEIRA_GAMEHUB_HOST_PID", String(pid), 1)
            hostPIDPublished = true
            LogStore.shared.log("[session-host] host process \(pid): its suspensions are real")
        }
        let text = (try? String(contentsOf: folder.appendingPathComponent("background.txt"), encoding: .utf8)) ?? ""
        guard text != lastBackground else { return }
        lastBackground = text
        let pids = text.split(whereSeparator: \.isNewline).compactMap { UInt32($0) }
        pids.withUnsafeBufferPointer { madeira_set_background_pids($0.baseAddress, Int32($0.count)) }
        LogStore.shared.log("[session-host] background processes: \(pids.isEmpty ? "none" : pids.map(String.init).joined(separator: " "))")
    }
    /// Ends the game and every program it started.
    static func close(_ token: Int) { send("close \(token)") }

    /// A command for the host: cmd-<n>.txt, which it takes in order.
    private static func send(_ command: String) {
        lastCommand += 1
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent("cmd.partial")
        try? (command + "\n").write(to: partial, atomically: false, encoding: .utf8)
        try? FileManager.default.moveItem(at: partial, to: folder.appendingPathComponent("cmd-\(lastCommand).txt"))
        LogStore.shared.log("[session-host] \(command)")
    }

    /// The exit of a job: nil while it runs; the exit code, or nil code when it did not start.
    static func result(of token: Int) -> (finished: Bool, code: UInt32?) {
        guard let text = try? String(contentsOf: exited(token), encoding: .utf8) else { return (false, nil) }
        let parts = text.split(separator: " ").map(String.init)
        guard parts.first == String(token) else { return (false, nil) }
        if parts.count > 1, parts[1] == "start-failed" { return (true, nil) }
        return (true, parts.count > 1 ? UInt32(parts[1]) : 0)
    }
}

extension LibraryEntry {
    /// What the host starts: the program and its arguments as one command line.
    var hostCommand: (line: String, exe: String) {
        let command = launchCommandForHost
        let quoted = command.exe.contains(" ") && !command.exe.hasPrefix("\"") ? "\"\(command.exe)\"" : command.exe
        return (command.args.isEmpty ? quoted : quoted + " " + command.args, command.exe)
    }
}
