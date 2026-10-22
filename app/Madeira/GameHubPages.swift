import SwiftUI
import UIKit

/// GamehubiOS's pages besides Library (GameHubHome.swift): Home, Ranking,
/// Profile, the full-screen Settings and Download Manager pages, and GameHub's
/// dialog and empty state.

// MARK: - Shared pieces

/// GameHub's empty-state mark: three bars and an exclamation mark.
struct GameHubEmptyIcon: View {
    var body: some View {
        if GHAsset.has("gh-empty") { GHImage(name: "gh-empty").frame(width: 64, height: 64) } else { drawn }
    }
    private var drawn: some View {
        let fill = LinearGradient(colors: [Color(white: 0.5), Color(white: 0.32)], startPoint: .top, endPoint: .bottom)
        return HStack(alignment: .bottom, spacing: 5) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 52, height: 9)
                RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 37, height: 9)
                RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 21, height: 9)
            }
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 5, height: 15)
                Circle().fill(fill).frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

struct GameHubEmptyState: View {
    let title: String
    let message: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            GameHubEmptyIcon().padding(.bottom, 10)
            Text(title).font(.system(size: 19)).foregroundStyle(Color.white.opacity(0.62))
            if !message.isEmpty {
                Text(message).font(.system(size: 14)).foregroundStyle(GameHub.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 480)
            }
            if let action {
                Button(action: action.1) {
                    Text(action.0).font(.system(size: 17, weight: .medium))
                        .frame(width: 166, height: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GameHub.postBlue))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain).padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// GameHub's dialog: an icon, a title, a message, Not now and a blue button.
struct GameHubDialog: View {
    struct Content: Equatable {
        var icon: String
        var title: String
        var message: String
        var primary: (String, () -> Void)?
        static func == (a: Content, b: Content) -> Bool { a.title == b.title && a.message == b.message }
    }
    let content: Content
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: dismiss)
            VStack(spacing: 0) {
                Image(systemName: content.icon).font(.system(size: 34)).symbolRenderingMode(.multicolor)
                    .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.3)).padding(.top, 26)
                Text(content.title).font(.system(size: 21, weight: .medium)).padding(.top, 14)
                Text(content.message).font(.system(size: 16)).foregroundStyle(Color.white.opacity(0.85))
                    .multilineTextAlignment(.center).padding(.top, 22).padding(.horizontal, 26)
                HStack(spacing: 18) {
                    Button(action: dismiss) {
                        Text(content.primary == nil ? "OK" : "Not now").font(.system(size: 17))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GameHub.button))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
                    }
                    if let primary = content.primary {
                        Button { dismiss(); primary.1() } label: {
                            Text(primary.0).font(.system(size: 17))
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GameHub.postBlue))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.18)))
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18).padding(.top, 34).padding(.bottom, 18)
            }
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(white: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.08)))
            .overlay(alignment: .topTrailing) {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 20, weight: .light)).padding(20) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
        }
    }
}

/// A page over the tabs: "‹ Title" and a soft glow behind, as GameHub's
/// Settings and Download Manager.
struct GameHubFullPage<Content: View>: View {
    let title: String
    let glow: Color
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            GameHub.background.ignoresSafeArea()
            RadialGradient(colors: [glow.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 520).ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.22).opacity(0.7), .clear], center: .bottomTrailing,
                           startRadius: 0, endRadius: 480).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                Button(action: close) {
                    HStack(spacing: 14) {
                        Image(systemName: "chevron.left").font(.system(size: 22, weight: .regular))
                        Text(title).font(.system(size: 25, weight: .regular))
                    }
                    .frame(height: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 44).padding(.top, 6)
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Home

/// Steam's store front (featuredcategories and appdetails, no key needed): the
/// top sellers with their tagline and genres, for Home's Recommended.
@MainActor final class GameHubStoreModel: ObservableObject {
    static let shared = GameHubStoreModel()
    struct Game: Identifiable, Hashable {
        let id: Int
        var name: String
        var image: URL?
        var tagline = ""
        var genres: [String] = []
    }
    @Published private(set) var games: [Game] = []
    @Published private(set) var error: String?
    private var loading = false

    func load() async {
        guard games.isEmpty, !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        struct Featured: Decodable {
            struct Section: Decodable { let items: [Item]? }
            struct Item: Decodable { let id: Int; let type: Int?; let name: String; let header_image: String? }
            let top_sellers: Section?
            let new_releases: Section?
        }
        do {
            let url = URL(string: "https://store.steampowered.com/api/featuredcategories?l=english")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let featured = try JSONDecoder().decode(Featured.self, from: data)
            var seen = Set<Int>()
            let items = ((featured.top_sellers?.items ?? []) + (featured.new_releases?.items ?? []))
                .filter { ($0.type ?? 0) == 0 && seen.insert($0.id).inserted }
                .prefix(12)
            games = items.map { Game(id: $0.id, name: $0.name, image: $0.header_image.flatMap(URL.init(string:))) }
            await loadDetails()
        } catch {
            self.error = "The Steam store could not be reached. Check the connection and try again."
            LogStore.shared.log("[gamehub-store] failed: \(error.localizedDescription)", level: .error)
        }
    }

    private func loadDetails() async {
        struct Details: Decodable {
            let success: Bool
            let data: Body?
            struct Body: Decodable { let short_description: String?; let genres: [Genre]? }
            struct Genre: Decodable { let description: String }
        }
        for (i, game) in games.enumerated() {
            guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(game.id)&l=english"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let body = (try? JSONDecoder().decode([String: Details].self, from: data))?[String(game.id)]?.data else { continue }
            guard games.indices.contains(i) else { return }
            games[i].tagline = body.short_description ?? ""
            games[i].genres = (body.genres ?? []).prefix(3).map(\.description)
        }
    }
}

/// Home: Recommended (Steam's top sellers), PC Games (yours) and Retro Games,
/// as GameHub's two-wide cards with a tagline over the art.
struct GameHubHomePage: View {
    @Binding var section: Int
    let games: [LibraryEntry]
    let open: (LibraryEntry) -> Void
    let play: (LibraryEntry) -> Void
    let openSteamApp: (Int) -> Void
    @ObservedObject private var store = GameHubStoreModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 56) {
                ForEach(Array(["Recommended", "PC Games", "Retro Games"].enumerated()), id: \.offset) { i, title in
                    Button { withAnimation(ConsoleHomeView.motion) { section = i } } label: {
                        VStack(spacing: 8) {
                            Text(title).font(.system(size: 20)).foregroundStyle(section == i ? Color.white : GameHub.secondary)
                            Capsule().fill(section == i ? Color.white : .clear).frame(width: 18, height: 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Group {
                switch section {
                case 0: recommended
                case 1: pcGames
                default:
                    GameHubEmptyState(title: "No retro games", message: "Retro consoles are not supported in GameHub yet.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 34)
        .task { await store.load() }
    }

    @ViewBuilder private var recommended: some View {
        if store.games.isEmpty, let error = store.error {
            GameHubEmptyState(title: "Couldn't load games", message: error)
        } else if store.games.isEmpty {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            cards(store.games.map { game in
                Card(id: "steam-\(game.id)", title: game.name, tagline: game.tagline, tags: game.genres,
                     art: AnyView(AsyncImage(url: game.image) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }),
                     tap: { openSteamApp(game.id) })
            })
        }
    }

    @ViewBuilder private var pcGames: some View {
        if games.isEmpty {
            GameHubEmptyState(title: "No games yet", message: "Import a game from Library, or install one from Steam.")
        } else {
            cards(games.map { entry in
                Card(id: ConsoleHomeView.key(entry), title: entry.title,
                     tagline: entry.lastPlayed.map { "Played \($0.formatted(.relative(presentation: .named)))" } ?? "",
                     tags: [entry.desktop == true ? "Windows Desktop" : entry.steamAppID != nil ? "Steam" : "PC Game"],
                     art: AnyView(LibraryArtwork(entry: entry, backdrop: true)),
                     tap: { entry.steamAppID == nil ? play(entry) : open(entry) })
            })
        }
    }

    struct Card: Identifiable {
        let id: String
        let title: String
        let tagline: String
        let tags: [String]
        let art: AnyView
        let tap: () -> Void
    }

    private func cards(_ list: [Card]) -> some View {
        GeometryReader { geo in
            let width = (geo.size.width - 18) / 2
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(list) { card in
                        Button(action: card.tap) { cardView(card, width: width, height: geo.size.height - 30) }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    private func cardView(_ card: Card, width: CGFloat, height: CGFloat) -> some View {
        let imageHeight = max(80, height - 112)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                card.art.frame(width: width - 12, height: imageHeight).clipped()
                if !card.tagline.isEmpty {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "quote.opening").font(.system(size: 13, weight: .black)).foregroundStyle(.white.opacity(0.8))
                        Text(card.tagline).font(.system(size: 17)).lineLimit(1)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                }
            }
            .frame(width: width - 12, height: imageHeight)
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 4, bottomTrailing: 4, topTrailing: 18), style: .continuous))
            .padding([.top, .horizontal], 6)
            Text(card.title).font(.system(size: 24, weight: .regular)).lineLimit(1).padding(.horizontal, 22).padding(.top, 14)
            Text(card.tags.joined(separator: "  ·  ")).font(.system(size: 15)).foregroundStyle(GameHub.secondary)
                .lineLimit(1).padding(.horizontal, 22).padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.08)))
    }
}

// MARK: - Ranking

/// Steam's most played games (ISteamChartsService, no key needed): "Hot" by
/// rank, "Soaring" by the places climbed since last week, and your own most
/// played when signed in.
@MainActor final class GameHubRankingModel: ObservableObject {
    static let shared = GameHubRankingModel()
    struct Rank: Identifiable, Hashable { let appID: Int; let rank: Int; let lastWeek: Int; let peak: Int; var id: Int { appID } }
    @Published private(set) var ranks: [Rank] = []
    @Published private(set) var names: [Int: String] = [:]
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var loaded: Date?

    func load(force: Bool = false) async {
        if !force, let loaded, Date().timeIntervalSince(loaded) < 600, !ranks.isEmpty { return }
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        struct Response: Decodable {
            struct Body: Decodable { let ranks: [Item]? }
            struct Item: Decodable { let rank: Int; let appid: Int; let last_week_rank: Int?; let peak_in_game: Int? }
            let response: Body
        }
        do {
            let url = URL(string: "https://api.steampowered.com/ISteamChartsService/GetMostPlayedGames/v1/")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let items = try JSONDecoder().decode(Response.self, from: data).response.ranks ?? []
            ranks = items.map { Rank(appID: $0.appid, rank: $0.rank, lastWeek: $0.last_week_rank ?? -1, peak: $0.peak_in_game ?? 0) }
            loaded = Date()
            LogStore.shared.log("[gamehub-ranking] \(ranks.count) games")
            await loadNames(ranks.prefix(40).map(\.appID))
        } catch {
            self.error = "Steam's charts could not be loaded. Check the connection and try again."
            LogStore.shared.log("[gamehub-ranking] failed: \(error.localizedDescription)", level: .error)
        }
    }

    /// Store names, one request each (appdetails answers one app per request).
    private func loadNames(_ ids: [Int]) async {
        struct Details: Decodable { let success: Bool; let data: Body?; struct Body: Decodable { let name: String } }
        for id in ids where names[id] == nil {
            if let owned = SteamOwnedLibrary.shared.game(id) { names[id] = owned.name; continue }
            guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(id)&filters=basic") else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let decoded = try? JSONDecoder().decode([String: Details].self, from: data),
               let name = decoded[String(id)]?.data?.name {
                names[id] = name
            }
        }
    }
}

struct GameHubRankingPage: View {
    let open: (Int) -> Void
    @ObservedObject private var ranking = GameHubRankingModel.shared
    @ObservedObject private var steam = SteamOwnedLibrary.shared

    private var hot: [GameHubRankingModel.Rank] { Array(ranking.ranks.prefix(20)) }
    private var soaring: [GameHubRankingModel.Rank] {
        Array(ranking.ranks.filter { $0.lastWeek > 0 && $0.lastWeek > $0.rank }
            .sorted { ($0.lastWeek - $0.rank) > ($1.lastWeek - $1.rank) }.prefix(20))
    }
    private var mine: [(Int, String)] {
        steam.playtime.filter { $0.value.minutes > 0 }.sorted { $0.value.minutes > $1.value.minutes }.prefix(20)
            .map { ($0.key, steam.game($0.key)?.name ?? "App \($0.key)") }
    }

    var body: some View {
        Group {
            if ranking.ranks.isEmpty, let error = ranking.error {
                GameHubEmptyState(title: "Couldn't load the ranking", message: error,
                                  action: ("Try again", { Task { await ranking.load(force: true) } }))
            } else if ranking.ranks.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        column("Hot", subtitle: "Most played on Steam", tint: Color(red: 1, green: 0.42, blue: 0.25)) {
                            ForEach(hot) { row($0.rank, $0.appID, detail: $0.peak > 0 ? "\($0.peak.formatted()) playing at peak" : nil) }
                        }
                        column("Soaring", subtitle: "Climbing this week", tint: Color(red: 0.3, green: 0.85, blue: 0.5)) {
                            ForEach(Array(soaring.enumerated()), id: \.element.id) { i, r in
                                row(i + 1, r.appID, detail: "▲ \(r.lastWeek - r.rank) places")
                            }
                        }
                        if !mine.isEmpty {
                            column("Yours", subtitle: "Your most played", tint: GameHub.link) {
                                ForEach(Array(mine.enumerated()), id: \.element.0) { i, item in
                                    row(i + 1, item.0, name: item.1, detail: steam.playtime[item.0]?.played)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 34).padding(.vertical, 12)
                }
            }
        }
        .task { await ranking.load() }
    }

    private func column<Rows: View>(_ title: String, subtitle: String, tint: Color, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .heavy)).foregroundStyle(tint)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(GameHub.secondary)
            }
            .padding(16)
            ScrollView { LazyVStack(spacing: 2) { rows() }.padding(.horizontal, 8).padding(.bottom, 10) }
        }
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.18), GameHub.tile], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(GameHub.tileStroke))
    }

    private func row(_ place: Int, _ appID: Int, name: String? = nil, detail: String?) -> some View {
        Button { open(appID) } label: {
            HStack(spacing: 12) {
                Text("\(place)").font(.system(size: 17, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(place <= 3 ? Color(red: 1, green: 0.78, blue: 0.3) : GameHub.secondary)
                    .frame(width: 26)
                AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/capsule_184x69.jpg")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.white.opacity(0.06) }
                .frame(width: 92, height: 35).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? ranking.names[appID] ?? "App \(appID)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(GameHub.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile

/// Profile, as GameHub lays it out: the account card, the Steam | Epic card,
/// and the social card on the right.
struct GameHubProfilePage: View {
    let games: Int
    let signIn: () -> Void
    let openSteam: () -> Void
    let community: () -> Void
    @ObservedObject private var steamAccount = SteamSignInModel.shared
    @ObservedObject private var steam = SteamOwnedLibrary.shared
    @ObservedObject private var jitState = LibraryJITState.shared
    @ObservedObject private var communityModel = CommunityModel.shared
    @State private var platform = 0

    private var name: String? { communityModel.account?.nickname ?? steamAccount.accountName }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    accountCard
                    platformCard
                }
                .padding(.bottom, 20)
            }
            socialCard
        }
        .padding(.horizontal, 34).padding(.top, 10)
        .onAppear { steamAccount.refresh() }
    }

    private var accountCard: some View {
        VStack(spacing: 14) {
            Button(action: signIn) {
                HStack(spacing: 18) {
                    ZStack {
                        if GHAsset.has("gh-avatar") {
                            GHImage(name: "gh-avatar").clipShape(Circle())
                        } else {
                            Circle().fill(LinearGradient(colors: [Color(red: 0.2, green: 0.55, blue: 0.95), Color(red: 0.95, green: 0.45, blue: 0.25)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "face.smiling.inverse").font(.system(size: 40)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 64, height: 64)
                    if let name {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.system(size: 22))
                            Text(jitState.enabled ? "JIT enabled · \(games) games" : "\(games) games")
                                .font(.system(size: 13)).foregroundStyle(GameHub.secondary)
                        }
                    } else {
                        (Text("Guest Mode").font(.system(size: 22)) + Text("(Tap to log in)").font(.system(size: 15)).foregroundColor(GameHub.secondary))
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            if name == nil {
                HStack(alignment: .top, spacing: 8) {
                    GHImage(name: "gh-guest-warning", fallback: "exclamationmark.triangle.fill").frame(width: 18, height: 18)
                        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.2))
                    Text("Steam Cloud saves and Steam games are unavailable until you sign in to Steam")
                        .foregroundStyle(GameHub.warning)
                }
                .font(.system(size: 15))
                .padding(.horizontal, 24).padding(.bottom, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(GameHub.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(GameHub.tileStroke))
    }

    private var platformCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                platformTab(0) { GameHubSteamMark().frame(width: 20, height: 20) }
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 18).padding(.bottom, 10)
                platformTab(1) { GameHubEpicMark().frame(width: 15, height: 18) }
            }
            .padding(.leading, 12)
            VStack(spacing: 14) {
                if platform == 1 {
                    Text("Epic Games").font(.system(size: 19)).foregroundStyle(Color.white.opacity(0.62))
                    Text("Binding an Epic account is not supported yet").font(.system(size: 16)).foregroundStyle(GameHub.secondary)
                } else if steamAccount.accountName == nil {
                    Text("Steam Data Sync").font(.system(size: 19)).foregroundStyle(Color.white.opacity(0.62))
                    Text("Bind account to view game library").font(.system(size: 17)).foregroundStyle(GameHub.secondary)
                    pill("Bind Steam Account", action: signIn)
                } else {
                    let minutes = steam.playtime.values.reduce(0) { $0 + $1.minutes }
                    HStack(spacing: 30) {
                        stat("\(steam.owned.count)", "Games")
                        stat("\(minutes / 60)", "Hours played")
                        stat("\(steam.downloads.count)", "Downloading")
                    }
                    pill("Open Steam Library", action: openSteam)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(GameHub.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(GameHub.tileStroke))
    }

    private func platformTab<Mark: View>(_ i: Int, @ViewBuilder mark: () -> Mark) -> some View {
        Button { platform = i } label: {
            VStack(spacing: 8) {
                mark().opacity(platform == i ? 1 : 0.6)
                Capsule().fill(platform == i ? Color.white : .clear).frame(width: 14, height: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 13)).foregroundStyle(GameHub.secondary)
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17)).padding(.horizontal, 28).frame(height: 44)
                .background(Capsule().fill(GameHub.button))
        }
        .buttonStyle(.plain)
    }

    private var socialCard: some View {
        VStack(spacing: 18) {
            GHImage(name: "gh-guest-social", fallback: "ellipsis.message.fill").frame(width: 50, height: 50)
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.45, green: 0.9, blue: 0.6), Color(red: 0.25, green: 0.7, blue: 0.45)],
                                                startPoint: .top, endPoint: .bottom))
            Text(communityModel.account == nil ? "Community isn't connected" : "Community")
                .font(.system(size: 22))
            Text(communityModel.account == nil
                 ? "Social features need GameHub's community servers, which this build does not connect to yet."
                 : "See the latest posts from the game circle.")
                .font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.75)).multilineTextAlignment(.center)
            pill("Open Community", action: community)
        }
        .padding(30)
        .frame(maxWidth: .infinity).frame(minHeight: 300)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(GameHub.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(GameHub.tileStroke))
    }
}

// MARK: - Download Manager

struct GameHubDownloadsPage: View {
    @ObservedObject private var steam = SteamOwnedLibrary.shared

    var body: some View {
        let ids = steam.downloads.keys.sorted()
        if ids.isEmpty {
            GameHubEmptyState(title: "No downloads", message: "")
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ids, id: \.self) { id in
                        if let download = steam.downloads[id] { row(id, download) }
                    }
                }
                .padding(.horizontal, 44).padding(.vertical, 12)
            }
        }
    }

    private func row(_ id: Int, _ download: SteamOwnedLibrary.Download) -> some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/capsule_184x69.jpg")) {
                $0.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color.white.opacity(0.06) }
            .frame(width: 138, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text(steam.game(id)?.name ?? "App \(id)").font(.system(size: 17, weight: .medium)).lineLimit(1)
                ProgressView(value: download.progress.fraction).tint(GameHub.link)
                Text(status(download)).font(.system(size: 13)).foregroundStyle(GameHub.secondary)
            }
            Button {
                if case .paused = download.state { steam.install(id) } else { steam.pause(id) }
            } label: {
                Image(systemName: { if case .paused = download.state { return "play.fill" } else { return "pause.fill" } }())
                    .frame(width: 44, height: 44).background(Circle().fill(GameHub.button))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func status(_ download: SteamOwnedLibrary.Download) -> String {
        let p = download.progress
        let size = ByteCountFormatter.string(fromByteCount: Int64(p.doneBytes), countStyle: .file) + " / "
            + ByteCountFormatter.string(fromByteCount: Int64(p.totalBytes), countStyle: .file)
        switch download.state {
        case .queued: return "Waiting"
        case .paused: return "Paused · " + size
        case .failed(let why): return "Failed: " + why
        case .active:
            let speed = p.bytesPerSecond > 0 ? " · " + ByteCountFormatter.string(fromByteCount: Int64(p.bytesPerSecond), countStyle: .file) + "/s" : ""
            return "\(Int(p.fraction * 100))% · " + size + speed
        }
    }
}
