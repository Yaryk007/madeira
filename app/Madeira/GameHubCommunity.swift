import SwiftUI

/// GameHub's Community tab: Following and Game Circle, the circle's sections
/// (All, then the ones you joined), and posts in two columns.
///
/// The posts come from a `CommunityService`. This build ships none: the tab
/// says that it is not connected instead of showing made-up posts. A service
/// sets `CommunityModel.shared.service` and the tab loads from it.
struct CommunityPost: Identifiable, Hashable {
    var id: String
    var author: String
    var avatar: URL?
    /// "Replied 1h ago", as the service words it.
    var activity: String
    var title: String
    var body: String
    var tags: [String]
    var images: [URL]
    /// GameHub's own account: an "Official" badge, and its tags as chips.
    var official = false
    var likes = 0
    var favorites = 0
    var comments = 0
    var shares = 0
}

struct CommunityComment: Identifiable, Hashable {
    var id: String
    var author: String
    var avatar: URL?
    var text: String
    var time: String
    var likes = 0
    var replies = 0
    var byAuthor = false
}

struct CommunitySection: Identifiable, Hashable {
    var id: String
    var name: String
    static let all = CommunitySection(id: "", name: "All")
}

struct CommunityAccount: Hashable {
    var nickname: String
    var avatar: URL?
}

protocol CommunityService {
    var account: CommunityAccount? { get }
    func sections() async throws -> [CommunitySection]
    func feed(following: Bool, section: CommunitySection, cursor: String?) async throws -> (posts: [CommunityPost], next: String?)
    func search(_ text: String) async throws -> [CommunityPost]
    func comments(_ post: CommunityPost, newest: Bool) async throws -> [CommunityComment]
}

@MainActor final class CommunityModel: ObservableObject {
    static let shared = CommunityModel()
    enum Feed: Int { case following, circle }
    enum State: Equatable { case notConnected, loading, loaded, failed(String) }

    var service: CommunityService? { didSet { account = service?.account; Task { await reload() } } }
    @Published private(set) var account: CommunityAccount?
    @Published var feed: Feed = .circle { didSet { if feed != oldValue { Task { await reload() } } } }
    @Published private(set) var sections: [CommunitySection] = [.all]
    @Published var section: CommunitySection = .all { didSet { if section != oldValue { Task { await reload() } } } }
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var state: State = .notConnected
    @Published var searching = false
    private var next: String?

    func reload() async {
        guard let service else { state = .notConnected; posts = []; return }
        state = .loading
        do {
            if sections.count <= 1 { sections = [.all] + (try await service.sections()) }
            let page = try await service.feed(following: feed == .following, section: section, cursor: nil)
            posts = page.posts; next = page.next; state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
            LogStore.shared.log("[community] load failed: \(error.localizedDescription)", level: .error)
        }
    }

    func loadMore() async {
        guard let service, let cursor = next, state == .loaded else { return }
        if let page = try? await service.feed(following: feed == .following, section: section, cursor: cursor) {
            posts += page.posts; next = page.next
        }
    }
}

struct GameHubCommunityPage: View {
    @ObservedObject private var model = CommunityModel.shared
    /// The feed scrolled down: Following / Game Circle slide away and the
    /// sections move up beside Post, as GameHub's header does.
    @State private var collapsed = false
    @State private var opened: CommunityPost?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 38) {
                if collapsed && model.feed == .circle {
                    sections.transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    feedTab("Following", .following)
                    feedTab("Game Circle", .circle)
                }
                Spacer()
                Button {} label: {
                    Label("Post", systemImage: "plus").labelStyle(.titleAndIcon)
                        .font(.system(size: 19, weight: .medium))
                        .padding(.horizontal, 20).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GameHub.postBlue))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .disabled(model.account == nil)
                .opacity(model.account == nil ? 0.55 : 1)
            }
            .padding(.top, 2)
            if model.feed == .circle && !collapsed {
                HStack(spacing: 28) {
                    sections
                    Button {} label: {
                        Label("Manage", systemImage: "line.3.horizontal.decrease").font(.system(size: 17))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.account == nil)
                }
                .padding(.top, 22)
                .transition(.opacity)
            }
            posts.padding(.top, 18)
        }
        .padding(.horizontal, GameHub.margin)
        .animation(.easeInOut(duration: 0.22), value: collapsed)
        .task { if model.state != .loaded { await model.reload() } }
        .fullScreenCover(item: $opened) { CommunityPostPage(post: $0) }
    }

    private var sections: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 28) {
                ForEach(model.sections) { s in
                    Button { model.section = s } label: {
                        Text(s.name).font(.system(size: 18, weight: .regular))
                            .foregroundStyle(s == model.section ? Color.white : GameHub.secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func feedTab(_ title: String, _ feed: CommunityModel.Feed) -> some View {
        let on = model.feed == feed
        return Button { withAnimation(ConsoleHomeView.motion) { model.feed = feed } } label: {
            VStack(spacing: 7) {
                Text(title).font(.system(size: on ? 25 : 20, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : GameHub.secondary)
                Capsule().fill(on ? Color.white : .clear).frame(width: 18, height: 4)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var posts: some View {
        switch model.state {
        case .notConnected:
            GameHubEmptyState(title: model.feed == .following ? "Nothing from your follows yet" : "Community isn't connected",
                              message: "This build of GameHub has no connection to GameHub's community servers yet, so there are no posts to show.",
                              action: model.feed == .following ? ("Discover", { withAnimation(ConsoleHomeView.motion) { model.feed = .circle } }) : nil)
        case .loading where model.posts.isEmpty:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where model.posts.isEmpty:
            GameHubEmptyState(title: "Couldn't load posts", message: message,
                              action: ("Try again", { Task { await model.reload() } }))
        default:
            if model.posts.isEmpty {
                GameHubEmptyState(title: model.feed == .following ? "Nothing from your follows yet" : "No posts yet",
                                  message: model.feed == .following ? "Follow creators you like, and their latest posts will show up here." : "",
                                  action: model.feed == .following ? ("Discover", { withAnimation(ConsoleHomeView.motion) { model.feed = .circle } }) : nil)
            } else {
                ScrollView {
                    GeometryReader { g in
                        Color.clear.preference(key: CommunityScrollOffset.self, value: g.frame(in: .named("community-feed")).minY)
                    }
                    .frame(height: 0)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)],
                              spacing: 16) {
                        ForEach(model.posts) { post in
                            CommunityPostCard(post: post).onTapGesture { opened = post }
                                .onAppear { if post.id == model.posts.last?.id { Task { await model.loadMore() } } }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .coordinateSpace(name: "community-feed")
                .onPreferenceChange(CommunityScrollOffset.self) { y in
                    let now = y < -40
                    if now != collapsed { collapsed = now }
                }
                .refreshable { await model.reload() }
            }
        }
    }
}

struct CommunityPostCard: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AsyncImage(url: post.avatar) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    Circle().fill(Color.white.opacity(0.1)).overlay(Image(systemName: "person.fill").foregroundStyle(GameHub.secondary))
                }
                .frame(width: 40, height: 40).clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(post.author).font(.system(size: 17, weight: .medium)).lineLimit(1)
                        if post.official {
                            Text("Official").font(.system(size: 11, weight: .medium)).italic()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(GameHub.postBlue))
                        }
                    }
                    Text(post.activity).font(.system(size: 13)).foregroundStyle(GameHub.secondary)
                }
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(GameHub.secondary)
            }
            if !post.title.isEmpty { Text(post.title).font(.system(size: 17, weight: .medium)).lineLimit(2) }
            if post.official {
                if !post.body.isEmpty {
                    Text(post.body).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(3)
                }
                if !post.tags.isEmpty {
                    // The official account's tags are chips, two to a row at most.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                        ForEach(post.tags, id: \.self) { tag in
                            Text("#" + tag).font(.system(size: 14)).foregroundStyle(GameHub.link).lineLimit(1)
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(GameHub.link.opacity(0.14)))
                        }
                    }
                }
            } else if !post.body.isEmpty || !post.tags.isEmpty {
                (Text(post.body) + Text(post.tags.map { " #" + $0 }.joined()).foregroundColor(GameHub.link))
                    .font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(4)
            }
            if let image = post.images.first {
                AsyncImage(url: image) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.06) }
                    .frame(maxWidth: 260).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 0) {
                CommunityCount(icon: "heart", value: post.likes)
                CommunityCount(icon: "star", value: post.favorites)
                CommunityCount(icon: "text.bubble", value: post.comments)
                CommunityCount(icon: "arrow.2.squarepath", value: post.shares)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(GameHub.tile.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(GameHub.tileStroke))
    }
}

struct CommunityScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// ♡ 598, ☆ 139 ... under a post.
struct CommunityCount: View {
    let icon: String
    let value: Int
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 15))
            Text(value.formatted()).font(.system(size: 15).monospacedDigit())
        }
        .foregroundStyle(Color.white.opacity(0.62))
        .frame(maxWidth: .infinity)
    }
}

/// A post opened: its images on the left, its comments (Hot · Newest) on the
/// right, the author with Follow on top, as GameHub's post page.
struct CommunityPostPage: View {
    let post: CommunityPost
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = CommunityModel.shared
    @State private var newest = false
    @State private var comments: [CommunityComment]?

    var body: some View {
        ZStack {
            LinearGradient(colors: [GameHub.background, Color(white: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 22)) }.buttonStyle(.plain)
                    AsyncImage(url: post.avatar) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Circle().fill(Color.white.opacity(0.1)) }
                        .frame(width: 36, height: 36).clipShape(Circle())
                    Text(post.author).font(.system(size: 19))
                    Text(post.activity).font(.system(size: 14)).foregroundStyle(GameHub.secondary)
                    Spacer()
                    Text("Follow").font(.system(size: 17)).padding(.horizontal, 22).frame(height: 38)
                        .background(Capsule().fill(GameHub.postBlue)).opacity(model.account == nil ? 0.55 : 1)
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold))
                }
                .padding(.horizontal, 44).padding(.vertical, 10)
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if !post.title.isEmpty { Text(post.title).font(.system(size: 20, weight: .medium)) }
                            if !post.body.isEmpty { Text(post.body).font(.system(size: 16)).foregroundStyle(.white.opacity(0.85)) }
                            ForEach(post.images, id: \.self) { url in
                                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: { Color.white.opacity(0.05).frame(height: 240) }
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 44).padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Comments \(post.comments)").font(.system(size: 18))
                            Spacer()
                            Button("Hot") { newest = false }.foregroundStyle(newest ? GameHub.secondary : Color.orange)
                            Text("·").foregroundStyle(GameHub.secondary)
                            Button("Newest") { newest = true }.foregroundStyle(newest ? Color.orange : GameHub.secondary)
                        }
                        .font(.system(size: 16)).buttonStyle(.plain)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                ForEach(comments ?? []) { c in comment(c) }
                                Text(comments == nil ? "Loading…" : "No more comments").font(.system(size: 14)).foregroundStyle(GameHub.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 44).padding(.vertical, 8)
                    .frame(width: 520)
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task(id: newest) { comments = (try? await model.service?.comments(post, newest: newest)) ?? [] }
    }

    private func comment(_ c: CommunityComment) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: c.avatar) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Circle().fill(Color.white.opacity(0.1)) }
                .frame(width: 44, height: 44).clipShape(Circle())
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(c.author).foregroundStyle(GameHub.secondary)
                    if c.byAuthor {
                        Text("Author").font(.system(size: 12)).foregroundStyle(Color.orange)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.15)))
                    }
                }
                .font(.system(size: 16))
                Text(c.text).font(.system(size: 17))
                HStack(spacing: 14) {
                    Text(c.time).foregroundStyle(GameHub.secondary)
                    Text("Reply")
                    Spacer()
                    Label("\(c.likes)", systemImage: "heart").foregroundStyle(GameHub.secondary)
                }
                .font(.system(size: 14))
                if c.replies > 0 {
                    HStack(spacing: 8) {
                        Rectangle().fill(GameHub.secondary).frame(width: 28, height: 1)
                        Text("\(c.replies) replies"); Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 14)).foregroundStyle(GameHub.secondary)
                }
            }
        }
    }
}
