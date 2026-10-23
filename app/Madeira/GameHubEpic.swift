// SPDX-License-Identifier: GPL-3.0-or-later
// GameHub: the Epic page (sign-in, library, install and play).

import SwiftUI
import WebKit

/// Library › Epic: GameHub's unbound page until an Epic account is bound, then
/// the owned games in GameHub's grid. A game not installed downloads on tap
/// (EpicInstaller); an installed one plays.
struct GameHubEpicContent: View {
    let tab: Int
    let play: (LibraryEntry) -> Void
    @ObservedObject private var store = EpicStore.shared
    @ObservedObject private var installer = EpicInstaller.shared
    @ObservedObject private var library = LibraryModel.shared
    @State private var login = false
    @State private var confirm: EpicGame?
    @State private var cancelling: EpicGame?

    private func installed(_ game: EpicGame) -> LibraryEntry? { library.entries.first { $0.epicApp == game.appName } }
    private var shown: [EpicGame] { tab == 0 ? store.games.filter { installed($0) != nil || installer.installing($0.appName) } : store.games }

    var body: some View {
        ZStack {
            if !store.signedIn {
                GameHubEpicUnbound(bind: { login = true })
            } else if store.games.isEmpty && store.loading {
                ProgressView("Loading your Epic library…").tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                GameHubEmptyState(title: tab == 0 ? "No Epic games installed" : "No Epic games",
                                  message: tab == 0 ? "Install one from All Games." : (store.error ?? "Games you own on Epic show up here."),
                                  action: tab == 0 ? nil : ("Refresh", refresh))
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 134, maximum: 134), spacing: 13)], alignment: .leading, spacing: 13) {
                        ForEach(shown) { game in
                            EpicGameCard(game: game, installed: installed(game) != nil, progress: installer.progress[game.appName])
                                .onTapGesture { tapped(game) }
                        }
                    }
                    .padding(.leading, 62).padding(.trailing, 58).padding(.top, 4).padding(.bottom, 30)
                }
                .refreshable { await store.refreshLibrary() }
            }
            if let game = confirm {
                GameHubNotice(title: "Install \(game.title)?",
                              message: "GameHub downloads it from Epic's servers into its drive C. Keep GameHub open while it downloads.",
                              confirm: "Install",
                              confirmed: { installer.install(game) { entry in library.save(entry) } },
                              dismiss: { confirm = nil })
            }
            if let game = cancelling {
                GameHubNotice(message: "Stop downloading \(game.title)? Finished files are kept, so it continues later.",
                              confirm: "Stop", confirmed: { installer.cancel(game.appName) }, dismiss: { cancelling = nil })
            }
        }
        .sheet(isPresented: $login) { EpicLoginSheet { code in login = false; Task { await store.signIn(code: code) } }.gameHubSheet() }
        .alert("Epic", isPresented: Binding(get: { installer.failure != nil }, set: { if !$0 { installer.failure = nil } })) {
            Button("OK", role: .cancel) { installer.failure = nil }
        } message: { Text(installer.failure?.message ?? "") }
        .task { if store.signedIn && store.games.isEmpty { await store.refreshLibrary() } }
    }

    private func refresh() { Task { await store.refreshLibrary() } }

    private func tapped(_ game: EpicGame) {
        if installer.installing(game.appName) { cancelling = game }
        else if let entry = installed(game) { play(entry) }
        else { confirm = game }
    }
}

/// An Epic game as GameHub's card: the art, the name, then its state.
struct EpicGameCard: View {
    let game: EpicGame
    let installed: Bool
    let progress: EpicInstaller.Progress?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: game.wide ?? game.cover) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.05) }
                .frame(height: 72).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(4)
            Text(game.title).font(.system(size: 15, weight: .bold)).lineLimit(1).padding(.horizontal, 11).padding(.top, 5)
            Group {
                if let progress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0).tint(GameHub.link)
                        Text(progress.total > 0 ? "\(Int(Double(progress.done) / Double(progress.total) * 100))%" : progress.phase)
                            .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: installed ? "play.fill" : "arrow.down.circle").font(.system(size: 12))
                        Text(installed ? "Play" : "Install").font(.system(size: 14))
                    }
                    .foregroundStyle(installed ? Color.white.opacity(0.8) : GameHub.link)
                }
            }
            .padding(.horizontal, 11).padding(.top, 7).padding(.bottom, 12)
        }
        .frame(width: 134)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Epic not bound, as GameHub's Epic page shows it.
struct GameHubEpicUnbound: View {
    let bind: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            GHImage(name: "gh-entry-epic", fallback: "e.square.fill").frame(width: 46, height: 46).saturation(0).opacity(0.7)
            Text("Epic data sync\nBind an account to view your personal game library")
                .font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.6)).multilineTextAlignment(.center).lineSpacing(3)
                .padding(.top, 16)
            Button(action: bind) {
                Text("Bind Epic Account").font(.system(size: 17)).padding(.horizontal, 24).frame(height: 48)
                    .background(Capsule().fill(GameHub.postBlue))
                    .overlay(Capsule().stroke(Color(red: 0.45, green: 0.75, blue: 1).opacity(0.6)))
            }
            .buttonStyle(GameHubPressStyle()).padding(.top, 12)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Epic's own sign-in page. After sign-in Epic shows a JSON page with a
/// one-time authorization code, which is read from it and handed back.
struct EpicLoginSheet: View {
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            EpicLoginWebView(done: done)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Sign in to Epic Games")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct EpicLoginWebView: UIViewRepresentable {
    let done: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) EpicGamesLauncher"
        view.load(URLRequest(url: EpicStore.loginURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let done: (String) -> Void
        private var finished = false
        init(done: @escaping (String) -> Void) { self.done = done }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished, let url = webView.url, url.path.contains("/id/api/redirect") else { return }
            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
                guard let self, !self.finished, let text = result as? String, let data = text.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let code = object["authorizationCode"] as? String, !code.isEmpty else { return }
                self.finished = true
                self.done(code)
            }
        }
    }
}
