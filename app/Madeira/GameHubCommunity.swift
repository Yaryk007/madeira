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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 38) {
                feedTab("Following", .following)
                feedTab("Game Circle", .circle)
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
            if model.feed == .circle {
                HStack(spacing: 28) {
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
                    Button {} label: {
                        Label("Manage", systemImage: "line.3.horizontal.decrease").font(.system(size: 17))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.account == nil)
                }
                .padding(.top, 22)
            }
            posts.padding(.top, 18)
        }
        .padding(.horizontal, 34)
        .task { if model.state != .loaded { await model.reload() } }
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
                              message: "This build of GamehubiOS has no connection to GameHub's community servers yet, so there are no posts to show.",
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
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)],
                              spacing: 16) {
                        ForEach(model.posts) { post in
                            CommunityPostCard(post: post)
                                .onAppear { if post.id == model.posts.last?.id { Task { await model.loadMore() } } }
                        }
                    }
                    .padding(.bottom, 20)
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(GameHub.tile.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(GameHub.tileStroke))
    }
}
