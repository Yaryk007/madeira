// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Glass: the Store tab. Browsing needs no account from the stores themselves, but
// Madeira only shows it once you are signed in, because everything here ends in your
// account: you buy or claim a game on the store's own page, it joins your library, and
// Madeira downloads it. Payment always happens on the store's site, never through Madeira.

import SwiftUI
import WebKit

enum GlassStoreKind: String, CaseIterable, Identifiable {
    case steam = "Steam", epic = "Epic", gog = "GOG"
    var id: String { rawValue }

    var home: URL {
        switch self {
        case .steam: return URL(string: "https://store.steampowered.com/")!
        case .epic: return URL(string: "https://store.epicgames.com/en-US/")!
        case .gog: return URL(string: "https://www.gog.com/en/games")!
        }
    }
    func search(_ text: String) -> URL {
        let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        switch self {
        case .steam: return URL(string: "https://store.steampowered.com/search/?term=\(q)")!
        case .epic: return URL(string: "https://store.epicgames.com/en-US/browse?q=\(q)")!
        case .gog: return URL(string: "https://www.gog.com/en/games?query=\(q)")!
        }
    }
}

struct GlassStoreItem: Identifiable, Hashable {
    var id: String { store.rawValue + key }
    var store: GlassStoreKind
    var key: String           // Steam app id, GOG product id, or Epic page slug
    var name: String
    var price: String
    var image: URL?
    var page: URL

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct GlassStoreShelf: Identifiable {
    var id: String { title }
    var title: String
    var items: [GlassStoreItem]
}

enum GlassStoreAPI {
    private static var country: String { Locale.current.region?.identifier ?? "US" }

    private static func money(_ cents: Int?, _ currency: String?) -> String {
        guard let cents, cents > 0 else { return "Free" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "Free"
    }

    static func json(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func steamItem(id: Int, name: String, cents: Int?, currency: String?) -> GlassStoreItem {
        GlassStoreItem(store: .steam, key: String(id), name: name, price: money(cents, currency),
                       image: SteamCatalog.cover(id), page: URL(string: "https://store.steampowered.com/app/\(id)/")!)
    }

    static func steamShelves() async throws -> [GlassStoreShelf] {
        let root = try await json(URL(string: "https://store.steampowered.com/api/featuredcategories/?cc=\(country)&l=english")!)
        var shelves: [GlassStoreShelf] = []
        for (key, title) in [("specials", "On sale"), ("top_sellers", "Top sellers"), ("new_releases", "New releases")] {
            guard let list = (root[key] as? [String: Any])?["items"] as? [[String: Any]] else { continue }
            var seen = Set<Int>()
            let items = list.compactMap { row -> GlassStoreItem? in
                guard let id = row["id"] as? Int, seen.insert(id).inserted else { return nil }
                return steamItem(id: id, name: row["name"] as? String ?? "", cents: row["final_price"] as? Int, currency: row["currency"] as? String)
            }
            if !items.isEmpty { shelves.append(GlassStoreShelf(title: title, items: items)) }
        }
        return shelves
    }

    static func steamSearch(_ text: String) async throws -> [GlassStoreItem] {
        var url = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        url.queryItems = [URLQueryItem(name: "term", value: text), URLQueryItem(name: "l", value: "english"), URLQueryItem(name: "cc", value: country)]
        let root = try await json(url.url!)
        return (root["items"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? Int else { return nil }
            let price = row["price"] as? [String: Any]
            return steamItem(id: id, name: row["name"] as? String ?? "", cents: price?["final"] as? Int, currency: price?["currency"] as? String)
        }
    }

    static func gog(query: String?, order: String) async throws -> [GlassStoreItem] {
        var url = URLComponents(string: "https://catalog.gog.com/v1/catalog")!
        var items = [URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "order", value: order),
                     URLQueryItem(name: "productType", value: "in:game,pack"), URLQueryItem(name: "countryCode", value: country),
                     URLQueryItem(name: "locale", value: "en-US"), URLQueryItem(name: "currencyCode", value: "USD")]
        if let query { items.append(URLQueryItem(name: "query", value: "like:" + query)) }
        url.queryItems = items
        let root = try await json(url.url!)
        return (root["products"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String, let name = row["title"] as? String else { return nil }
            let price = (row["price"] as? [String: Any])?["final"] as? String
            let cover = (row["coverVertical"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "{formatter}", with: "")) }
            let page = (row["storeLink"] as? String).flatMap(URL.init(string:)) ?? GlassStoreKind.gog.home
            return GlassStoreItem(store: .gog, key: id, name: name, price: price ?? "Free", image: cover, page: page)
        }
    }

    static func gogShelves() async throws -> [GlassStoreShelf] {
        async let trending = gog(query: nil, order: "desc:trending")
        async let discounts = gog(query: nil, order: "desc:discount")
        return [GlassStoreShelf(title: "Trending", items: try await trending), GlassStoreShelf(title: "Biggest discounts", items: try await discounts)]
            .filter { !$0.items.isEmpty }
    }

    /// Epic has no open catalogue, only this list of the current free games; everything else is on its site.
    static func epicShelves() async throws -> [GlassStoreShelf] {
        let url = URL(string: "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=en-US&country=\(country)&allowCountries=\(country)")!
        let root = try await json(url)
        let store = (((root["data"] as? [String: Any])?["Catalog"] as? [String: Any])?["searchStore"] as? [String: Any])
        let elements = store?["elements"] as? [[String: Any]] ?? []
        let items = elements.compactMap { row -> GlassStoreItem? in
            guard let name = row["title"] as? String, row["promotions"] is [String: Any] else { return nil }
            let mappings = (row["catalogNs"] as? [String: Any])?["mappings"] as? [[String: Any]]
            guard let slug = (mappings?.first?["pageSlug"] as? String) ?? (row["productSlug"] as? String), !slug.isEmpty else { return nil }
            let images = row["keyImages"] as? [[String: Any]] ?? []
            let tall = images.first { $0["type"] as? String == "OfferImageTall" } ?? images.first
            let total = ((row["price"] as? [String: Any])?["totalPrice"] as? [String: Any])?["fmtPrice"] as? [String: Any]
            let price = total?["discountPrice"] as? String ?? "Free"
            return GlassStoreItem(store: .epic, key: slug, name: name, price: price == "0" ? "Free" : price,
                                  image: (tall?["url"] as? String).flatMap(URL.init(string:)),
                                  page: URL(string: "https://store.epicgames.com/en-US/p/\(slug)")!)
        }
        return items.isEmpty ? [] : [GlassStoreShelf(title: "Free this week", items: items)]
    }
}

/// A game's store page, read from the store's public API and drawn natively.
struct GlassStoreDetails {
    var description: String
    var screenshots: [URL]
    var facts: [(String, String)]
}

extension GlassStoreAPI {
    static func details(_ item: GlassStoreItem) async -> GlassStoreDetails? {
        switch item.store {
        case .steam:
            guard let root = try? await json(URL(string: "https://store.steampowered.com/api/appdetails?appids=\(item.key)&l=english")!),
                  let entry = root[item.key] as? [String: Any], entry["success"] as? Bool == true,
                  let d = entry["data"] as? [String: Any] else { return nil }
            var facts: [(String, String)] = []
            if let devs = d["developers"] as? [String], let first = devs.first { facts.append(("Developer", first)) }
            if let date = (d["release_date"] as? [String: Any])?["date"] as? String { facts.append(("Released", date)) }
            if let genres = d["genres"] as? [[String: Any]] {
                let names = genres.compactMap { $0["description"] as? String }.prefix(3)
                if !names.isEmpty { facts.append(("Genre", names.joined(separator: ", "))) }
            }
            let shots = (d["screenshots"] as? [[String: Any]] ?? []).compactMap { ($0["path_thumbnail"] as? String).flatMap(URL.init(string:)) }
            return GlassStoreDetails(description: d["short_description"] as? String ?? "", screenshots: Array(shots.prefix(8)), facts: facts)
        case .gog:
            guard let root = try? await json(URL(string: "https://api.gog.com/products/\(item.key)?expand=description,screenshots")!) else { return nil }
            let lead = ((root["description"] as? [String: Any])?["lead"] as? String ?? "")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let shots = (root["screenshots"] as? [[String: Any]] ?? []).compactMap { shot -> URL? in
                guard let template = shot["formatter_template_url"] as? String else { return nil }
                return URL(string: template.replacingOccurrences(of: "{formatter}", with: "ggvgm"))
            }
            var facts: [(String, String)] = []
            if let date = root["release_date"] as? String { facts.append(("Released", String(date.prefix(10)))) }
            return GlassStoreDetails(description: lead, screenshots: Array(shots.prefix(8)), facts: facts)
        case .epic:
            return nil
        }
    }
}

/// A store's page in Madeira, keeping its own sign-in between visits. Buying happens here,
/// on the store's own site; closing it refreshes that store's games.
struct GlassWebStore: View {
    let title: String
    let url: URL
    var closed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = GlassBrowser()

    var body: some View {
        ZStack(alignment: .top) {
            GlassWebView(url: url, browser: browser).ignoresSafeArea(edges: .bottom).padding(.top, 52)
            HStack(spacing: 8) {
                Button { browser.web?.goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(GlassButtonStyle(compact: true)).disabled(!browser.canGoBack).accessibilityLabel("Back")
                Text(browser.title.isEmpty ? title : browser.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                if browser.loading { ProgressView() }
                Button("Done") { dismiss() }.buttonStyle(GlassButtonStyle(compact: true))
            }.padding(.horizontal, 16).frame(height: 48)
        }
        .glassPointer { dismiss() }
        .onDisappear(perform: closed)
    }
}

@MainActor final class GlassBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var title = ""
    @Published var loading = true
    @Published var canGoBack = false
    weak var web: WKWebView?

    private func update(_ view: WKWebView) {
        title = view.title ?? ""; loading = view.isLoading; canGoBack = view.canGoBack
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { update(webView) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { update(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { update(webView) }
    /// Sign-in and payment pop-ups open in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

struct GlassWebView: UIViewRepresentable {
    let url: URL
    let browser: GlassBrowser
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = browser
        view.uiDelegate = browser
        view.allowsBackForwardNavigationGestures = true
        browser.web = view
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
