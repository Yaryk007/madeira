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
    /// Where the glow sits: Settings' is in the middle, Download Manager's top left.
    var glowCenter: UnitPoint = .topLeading
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255).ignoresSafeArea()
            RadialGradient(colors: [glow, .clear], center: glowCenter, startRadius: 0, endRadius: glowCenter == .center ? 430 : 520).ignoresSafeArea()
            if glowCenter != .center {
                RadialGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.22).opacity(0.7), .clear], center: .bottomTrailing,
                               startRadius: 0, endRadius: 480).ignoresSafeArea()
            }
            VStack(alignment: .leading, spacing: 0) {
                // GameHub's page title: ‹ and the name in bold, 27 pt down.
                Button(action: close) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                        Text(title).font(.system(size: 24, weight: .bold))
                    }
                    .frame(height: 54).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 61)
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.container, edges: .horizontal)
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
    /// PC Games' shelves, as GameHub's store page: Trending first, then grids.
    struct Shelf: Identifiable { let title: String; var games: [Game]; var id: String { title } }
    @Published private(set) var shelves: [Shelf] = []
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
            let specials: Section?
            let coming_soon: Section?
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
            func shelf(_ title: String, _ section: Featured.Section?, _ count: Int) -> Shelf? {
                var seen = Set<Int>()
                let list = (section?.items ?? []).filter { ($0.type ?? 0) == 0 && seen.insert($0.id).inserted }.prefix(count)
                    .map { Game(id: $0.id, name: $0.name, image: $0.header_image.flatMap(URL.init(string:))) }
                return list.isEmpty ? nil : Shelf(title: title, games: Array(list))
            }
            shelves = [shelf("Trending", featured.top_sellers, 10), shelf("On Sale", featured.specials, 10),
                       shelf("New Releases", featured.new_releases, 10), shelf("Coming Soon", featured.coming_soon, 10)].compactMap { $0 }
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
        // Every game once: the Recommended cards first, then the shelves.
        var ids: [Int] = games.map(\.id)
        for shelf in shelves { for game in shelf.games where !ids.contains(game.id) { ids.append(game.id) } }
        for id in ids.prefix(48) {
            guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(id)&l=english"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let body = (try? JSONDecoder().decode([String: Details].self, from: data))?[String(id)]?.data else { continue }
            let tagline = body.short_description ?? "", genres = (body.genres ?? []).prefix(3).map(\.description)
            for i in games.indices where games[i].id == id { games[i].tagline = tagline; games[i].genres = genres }
            for s in shelves.indices {
                for i in shelves[s].games.indices where shelves[s].games[i].id == id {
                    shelves[s].games[i].tagline = tagline; shelves[s].games[i].genres = genres
                }
            }
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
            HStack(spacing: 24) {
                ForEach(Array(["Recommended", "PC Games", "Retro Games"].enumerated()), id: \.offset) { i, title in
                    Button { withAnimation(ConsoleHomeView.motion) { section = i } } label: {
                        VStack(spacing: 5) {
                            Text(title).font(.system(size: 18, weight: section == i ? .bold : .regular))
                                .foregroundStyle(section == i ? Color.white : Color.white.opacity(0.5))
                            Capsule().fill(section == i ? Color.white : .clear).frame(width: 15, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2).padding(.bottom, 6)
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
        .padding(.horizontal, GameHub.margin)
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

    /// GameHub's PC Games: a Trending row of wide cards tinted with their art's
    /// colour, then shelves of small cards five to a row. Steam's store feed
    /// stands in for GameHub's own catalogue.
    @ViewBuilder private var pcGames: some View {
        if store.shelves.isEmpty, let error = store.error {
            GameHubEmptyState(title: "Couldn't load games", message: error)
        } else if store.shelves.isEmpty {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.shelves.enumerated()), id: \.element.id) { i, shelf in
                        Text(shelf.title).font(.system(size: 20, weight: .bold)).padding(.top, i == 0 ? 14 : 30).padding(.bottom, 12)
                        if i == 0 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(shelf.games) { game in
                                        Button { openSteamApp(game.id) } label: { GameHubTrendingCard(game: game) }.buttonStyle(GameHubPressStyle())
                                    }
                                }
                            }
                            .scrollClipDisabled()
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 5), spacing: 11) {
                                ForEach(shelf.games.prefix(10)) { game in
                                    Button { openSteamApp(game.id) } label: { GameHubShelfCard(game: game) }.buttonStyle(GameHubPressStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
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
    @State private var filter = 0

    private struct Item: Identifiable { let id: Int; let place: Int; let name: String; let detail: String; let value: String }

    /// GameHub's chips over Steam's charts: most played now, climbing this week, and yours.
    private var filters: [String] { mine.isEmpty ? ["Recently Hot", "Rising"] : ["Recently Hot", "Rising", "Your Games"] }
    private var mine: [(Int, String)] {
        steam.playtime.filter { $0.value.minutes > 0 }.sorted { $0.value.minutes > $1.value.minutes }.prefix(20)
            .map { ($0.key, steam.game($0.key)?.name ?? "App \($0.key)") }
    }
    private var items: [Item] {
        switch filter {
        case 1:
            return ranking.ranks.filter { $0.lastWeek > 0 && $0.lastWeek > $0.rank }
                .sorted { ($0.lastWeek - $0.rank) > ($1.lastWeek - $1.rank) }.prefix(20).enumerated()
                .map { i, r in Item(id: r.appID, place: i + 1, name: ranking.names[r.appID] ?? "App \(r.appID)",
                                    detail: "Up \(r.lastWeek - r.rank) places this week", value: "▲\(r.lastWeek - r.rank)") }
        case 2:
            return mine.enumerated().map { i, item in
                Item(id: item.0, place: i + 1, name: item.1, detail: steam.playtime[item.0]?.played ?? "", value: "") }
        default:
            return ranking.ranks.prefix(30).map { r in
                Item(id: r.appID, place: r.rank, name: ranking.names[r.appID] ?? "App \(r.appID)",
                     detail: r.peak > 0 ? "\(r.peak.formatted()) playing at peak" : "Most played on Steam",
                     value: r.peak > 0 ? Self.compact(r.peak) : "") }
        }
    }

    var body: some View {
        ZStack {
            // The warm backdrop is GameHubHomeView's (behind the top bar too).
            if ranking.ranks.isEmpty, let error = ranking.error {
                GameHubEmptyState(title: "Couldn't load the ranking", message: error,
                                  action: ("Try again", { Task { await ranking.load(force: true) } }))
            } else if ranking.ranks.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.top, 10)
                        chips.padding(.top, 9)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 8) {
                            ForEach(items) { row($0) }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, GameHub.margin).padding(.top, 11).padding(.bottom, 30)
                }
            }
        }
        .task { await ranking.load() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GameHub Top Picks").font(.system(size: 22, weight: .bold))
                Text(filter == 2 ? "Your most played" : "Top Games (Last 7 Days)").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(Array(filters.enumerated()), id: \.offset) { i, name in Button(name) { filter = i } }
            } label: {
                HStack(spacing: 10) {
                    Text("Top Picks").font(.system(size: 17))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 15).frame(height: 31)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.2)))
            }
            .foregroundStyle(.white)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(filters.enumerated()), id: \.offset) { i, name in
                    let on = i == filter
                    Button { withAnimation(.easeInOut(duration: 0.15)) { filter = i } } label: {
                        Text(name).font(.system(size: 17))
                            .foregroundStyle(on ? Color(red: 1, green: 0.78, blue: 0.62) : Color.white.opacity(0.65))
                            .padding(.horizontal, 15).frame(height: 31)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(on ? Color(red: 0.9, green: 0.45, blue: 0.2).opacity(0.22) : Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(on ? Color(red: 0.95, green: 0.55, blue: 0.3) : Color.white.opacity(0.14), lineWidth: on ? 1.3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func row(_ item: Item) -> some View {
        Button { open(item.id) } label: {
            HStack(spacing: 10) {
                medal(item.place).frame(width: 36)
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(item.id)/library_600x900.jpg")) { phase in
                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                        else if phase.error != nil {
                            AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(item.id)/header.jpg")) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Color.white.opacity(0.06) }
                        } else { Color.white.opacity(0.06) }
                    }
                    .frame(width: 56, height: 71).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.system(size: 18, weight: .bold)).lineLimit(1)
                        Text(item.detail).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if !item.value.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: filter == 1 ? "arrow.up.right" : "flame.fill").font(.system(size: 13))
                            Text(item.value).font(.system(size: 18, weight: .bold)).monospacedDigit()
                        }
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.2))
                    }
                }
                .padding(.leading, 8).padding(.trailing, 14).frame(height: 87)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 1, green: 0.8, blue: 0.6).opacity(item.place <= 3 ? 0.07 : 0.04)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GameHubPressStyle())
    }

    /// GameHub's TOP medals for the first three, the place number after.
    @ViewBuilder private func medal(_ place: Int) -> some View {
        if place <= 3 {
            let colors: [Color] = [Color(red: 1, green: 0.72, blue: 0.2), Color(red: 0.72, green: 0.78, blue: 0.86), Color(red: 0.88, green: 0.55, blue: 0.3)]
            VStack(spacing: 2) {
                Text("TOP").font(.system(size: 11, weight: .heavy))
                ZStack {
                    Image(systemName: "shield.fill").font(.system(size: 20)).foregroundStyle(colors[place - 1])
                    Text("\(place)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white).offset(y: -1)
                }
            }
        } else {
            Text("\(place)").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.white.opacity(0.75)).monospacedDigit()
        }
    }

    static func compact(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : n >= 1_000 ? String(format: "%.0fK", Double(n) / 1_000) : "\(n)"
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
        .padding(.horizontal, GameHub.margin).padding(.top, 0)
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
                    .frame(width: 54, height: 54)
                    if let name {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.system(size: 22))
                            Text(jitState.enabled ? "JIT enabled · \(games) games" : "\(games) games")
                                .font(.system(size: 13)).foregroundStyle(GameHub.secondary)
                        }
                    } else {
                        (Text("Guest Mode").font(.system(size: 20, weight: .semibold)) + Text("(Tap to log in)").font(.system(size: 14)).foregroundColor(GameHub.secondary))
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

/// PC Games' Trending card: the art on top, the name and tagline on a plate
/// tinted with the art's own colour.
struct GameHubTrendingCard: View {
    let game: GameHubStoreModel.Game
    @State private var image: UIImage?
    @State private var tint = Color(white: 0.2)
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill) } else { Color.white.opacity(0.05) }
            }
            .frame(width: 214, height: 110).clipped()
            VStack(alignment: .leading, spacing: 5) {
                Text(game.name).font(.system(size: 17, weight: .bold)).lineLimit(1)
                Text(game.tagline).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(width: 214, height: 191, alignment: .top)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: game.id) {
            guard image == nil, let url = game.image, let (data, _) = try? await URLSession.shared.data(from: url),
                  let loaded = UIImage(data: data) else { return }
            image = loaded
            tint = GameHubTint.color(of: loaded)
        }
    }
}

/// A shelf card: the art inset at the top, the name, then the tagline.
struct GameHubShelfCard: View {
    let game: GameHubStoreModel.Game
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: game.image) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                .frame(height: 74).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(4)
            Text(game.name).font(.system(size: 16)).lineLimit(1).padding(.horizontal, 8).padding(.top, 4)
            Text(game.tagline).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1)))
    }
}

/// The average colour of an image, darkened, for GameHub's tinted card plates.
enum GameHubTint {
    static func color(of image: UIImage) -> Color {
        guard let cg = image.cgImage else { return Color(white: 0.2) }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Color(white: 0.2) }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let scale = 0.42
        return Color(red: Double(pixel[0]) / 255 * scale, green: Double(pixel[1]) / 255 * scale, blue: Double(pixel[2]) / 255 * scale)
    }
}
