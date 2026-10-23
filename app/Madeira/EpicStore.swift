// SPDX-License-Identifier: GPL-3.0-or-later
// GameHub: Epic Games Store sign-in, library and launch arguments.
//
// The flow is the one the open-source launchers (Legendary, Heroic) use with
// the Epic Games Launcher's public client: the player signs in on Epic's own
// page, its one-time authorization code becomes a token pair, the refresh
// token stays in this device's Keychain, and a fresh exchange code goes to
// each game at launch as the Epic launcher passes it.

import Foundation
import Security

enum EpicError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// One owned game from the library service, with its catalog title and art.
struct EpicGame: Identifiable, Hashable, Codable {
    var id: String { appName }
    let appName: String
    let namespace: String
    let catalogItemId: String
    var title: String
    var cover: URL?
    var wide: URL?
}

@MainActor final class EpicStore: ObservableObject {
    static let shared = EpicStore()

    // The Epic Games Launcher's public client (as Legendary and Heroic use it).
    private static let clientID = "34a02cf8f4414e29b15921876da36f9a"
    private static let clientSecret = "daafbccc737745039dffe53d94fc76cf"
    private static let oauthHost = "https://account-public-service-prod03.ol.epicgames.com"
    static let loginURL = URL(string: "https://www.epicgames.com/id/login?redirectUrl="
        + "https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D\(clientID)%26responseType%3Dcode")!

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var accountID: String
        var displayName: String
        var expires: Date
    }

    @Published private(set) var session: Session?
    @Published private(set) var games: [EpicGame] = []
    @Published private(set) var loading = false
    @Published var error: String?

    var signedIn: Bool { session != nil }

    private init() {
        session = EpicKeychain.load()
        games = (try? JSONDecoder().decode([EpicGame].self, from: Data(contentsOf: Self.cacheURL))) ?? []
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("gamehub-epic-library.json")
    }

    // MARK: Sign-in

    /// The authorization code from Epic's redirect page becomes the session.
    func signIn(code: String) async {
        do {
            try await token(["grant_type": "authorization_code", "code": code, "token_type": "eg1"])
            LogStore.shared.log("[epic] signed in as \(session?.displayName ?? "?")")
            await refreshLibrary()
        } catch {
            self.error = error.localizedDescription
            LogStore.shared.log("[epic] sign-in failed: \(error.localizedDescription)", level: .error)
        }
    }

    func signOut() {
        session = nil; games = []
        EpicKeychain.delete()
        try? FileManager.default.removeItem(at: Self.cacheURL)
        LogStore.shared.log("[epic] signed out")
    }

    private func token(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: Self.oauthHost + "/account/api/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("basic " + Data("\(Self.clientID):\(Self.clientSecret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, let refresh = object["refresh_token"] as? String else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errorMessage"] as? String
            throw EpicError.message(message ?? "Epic did not accept the sign-in (HTTP \(status)).")
        }
        let expiresIn = object["expires_in"] as? Double ?? 7200
        session = Session(accessToken: access, refreshToken: refresh,
                          accountID: object["account_id"] as? String ?? "",
                          displayName: object["displayName"] as? String ?? "Epic player",
                          expires: Date().addingTimeInterval(expiresIn - 120))
        if let session { EpicKeychain.save(session) }
    }

    /// A valid access token, refreshed when it has expired.
    func accessToken() async throws -> String {
        guard let session else { throw EpicError.message("Sign in to Epic first.") }
        if session.expires > Date() { return session.accessToken }
        do {
            try await token(["grant_type": "refresh_token", "refresh_token": session.refreshToken, "token_type": "eg1"])
        } catch {
            signOut()
            throw EpicError.message("Your Epic sign-in expired. Sign in again.")
        }
        return self.session?.accessToken ?? ""
    }

    func get(_ url: String) async throws -> Any { try await Self.fetch(url, token: try await accessToken()) }

    nonisolated static func fetch(_ url: String, token: String) async throws -> Any {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw EpicError.message("Epic's servers answered HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: Library

    func refreshLibrary() async {
        guard signedIn, !loading else { return }
        loading = true; defer { loading = false }
        do {
            var records: [[String: Any]] = [], cursor: String?
            repeat {
                var url = "https://library-service.live.use1a.on.epicgames.com/library/api/public/items?includeMetadata=true"
                if let cursor { url += "&cursor=" + (cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? cursor) }
                let page = try await get(url) as? [String: Any] ?? [:]
                records += page["records"] as? [[String: Any]] ?? []
                cursor = (page["responseMetadata"] as? [String: Any])?["nextCursor"] as? String
            } while cursor != nil && records.count < 5000
            // Unreal Engine marketplace assets live in the "ue" namespace; a record without an app is not installable.
            let owned = records.compactMap { r -> (String, String, String)? in
                guard let app = r["appName"] as? String, let ns = r["namespace"] as? String, let item = r["catalogItemId"] as? String,
                      ns != "ue" else { return nil }
                return (app, ns, item)
            }
            // Catalog details eight at a time (libraries with hundreds of free games are common).
            let token = try await accessToken()
            var infos: [String: [String: Any]] = [:]
            var queue = owned[...]
            await withTaskGroup(of: (String, [String: Any]?).self) { group in
                func add() {
                    guard let (_, ns, item) = queue.popFirst() else { return }
                    group.addTask {
                        let url = "https://catalog-public-service-prod06.ol.epicgames.com/catalog/api/shared/namespace/\(ns)/bulk/items"
                            + "?id=\(item)&includeDLCDetails=true&includeMainGameDetails=true&country=US&locale=en"
                        let object = try? await EpicStore.fetch(url, token: token) as? [String: Any]
                        return (item, object?[item] as? [String: Any])
                    }
                }
                for _ in 0..<8 { add() }
                for await (item, info) in group { if let info { infos[item] = info }; add() }
            }
            var list: [EpicGame] = []
            for (app, ns, item) in owned {
                guard let info = infos[item] else { continue }
                // DLC points at its main game; only games and applications are listed.
                if info["mainGameItem"] != nil { continue }
                let categories = (info["categories"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                if !categories.isEmpty && !categories.contains("games") && !categories.contains("applications") { continue }
                let images = info["keyImages"] as? [[String: Any]] ?? []
                func image(_ types: [String]) -> URL? {
                    for type in types { if let u = images.first(where: { $0["type"] as? String == type })?["url"] as? String { return URL(string: u) } }
                    return nil
                }
                list.append(EpicGame(appName: app, namespace: ns, catalogItemId: item, title: info["title"] as? String ?? app,
                                     cover: image(["DieselGameBoxTall", "OfferImageTall", "Thumbnail"]),
                                     wide: image(["DieselGameBox", "OfferImageWide", "DieselStoreFrontWide"])))
            }
            games = list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            try? JSONEncoder().encode(games).write(to: Self.cacheURL, options: .atomic)
            error = nil
            LogStore.shared.log("[epic] library: \(games.count) games of \(records.count) records")
        } catch {
            self.error = error.localizedDescription
            LogStore.shared.log("[epic] library failed: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: Launch

    /// The Epic launcher's arguments for a game: a one-time exchange code and the
    /// account, so the game signs in to Epic Online Services on its own.
    func launchArguments(for game: (app: String, namespace: String)) async throws -> String {
        let code = (try await get(Self.oauthHost + "/account/api/oauth/exchange") as? [String: Any])?["code"] as? String ?? ""
        guard let session, !code.isEmpty else { throw EpicError.message("Epic did not give a launch code. Sign in again.") }
        let name = session.displayName.replacingOccurrences(of: "\"", with: "")
        return "-AUTH_LOGIN=unused -AUTH_PASSWORD=\(code) -AUTH_TYPE=exchangecode -epicapp=\(game.app) -epicenv=Prod -EpicPortal "
            + "-epicusername=\"\(name)\" -epicuserid=\(session.accountID) -epiclocale=en -epicsandboxid=\(game.namespace)"
    }

    /// Arguments added to one launch only; never saved with the library entry.
    nonisolated(unsafe) static var pendingArguments: [UUID: String] = [:]
}

/// The Epic refresh token, this device only.
enum EpicKeychain {
    private static let service = "gamehub.epic"
    static func save(_ session: EpicStore.Session) {
        delete()
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                    kSecAttrAccount as String: "session", kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
    }
    static func load() -> EpicStore.Session? {
        var result: AnyObject?
        let status = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                          kSecAttrAccount as String: "session", kSecReturnData as String: true,
                                          kSecMatchLimit as String: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(EpicStore.Session.self, from: data)
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: "session"] as CFDictionary)
    }
}
