import SwiftUI

/// One folder screen.
///
/// It shows one of the three views (`explore` / `album` / `image`) and carries
/// the switcher that moves between them, plus `random` — which is an action, not
/// a fourth view. See CONTEXT.md and docs/adr/0007.
///
/// All of its chrome is self-drawn and floats over the wall: there is no toolbar
/// and no navigation bar. The wall is the product; the chrome gets out of its
/// way while scrolling down and comes back at rest.
struct FolderView: View {
    let client: GalleryClient
    @Binding var drawerOpen: Bool

    @State private var store: FolderStore
    @State private var scroll = ScrollIntent()
    /// Held for as long as the random viewer is open — it is the sequence.
    @State private var randomStream: RandomStream?

    @Environment(Navigator.self) private var navigator
    @Environment(TreeStore.self) private var treeStore
    @Environment(ViewerPresenter.self) private var presenter
    @Environment(\.dismiss) private var dismiss

    private let columns = WallColumns.shared

    init(path: String, view: FolderViewKind, client: GalleryClient, drawerOpen: Binding<Bool>) {
        self.client = client
        _drawerOpen = drawerOpen
        _store = State(initialValue: FolderStore(path: path, view: view, client: client))
    }

    var body: some View {
        content
            .overlay(alignment: .top) { topChrome }
            .overlay(alignment: .bottom) { bottomChrome }
            .task { await store.loadInitial() }
            #if os(iOS)
            // The self-drawn top bar replaces it. Left-edge swipe still pops —
            // that gesture stays with the system, which is why the drawer opens
            // from a button instead of from the edge.
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationTitle(store.displayName)
            // The leaf test needs the tree, and the tree arrives after the first
            // render — so a folder can start out offering all three views and
            // then turn out to be a leaf. Without this the switcher ends up with
            // no cell selected and no way back to a valid one.
            .onChange(of: availableViews, initial: true) { _, views in
                guard !views.contains(store.view), let fallback = views.first else { return }
                store.view = fallback
            }
    }

    // MARK: - Wall

    @ViewBuilder
    private var content: some View {
        if let error = store.error, store.entries.isEmpty {
            ErrorStateView(error: error) {
                Task { await store.reload() }
            }
        } else if store.entries.isEmpty, store.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.entries.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "photo.on.rectangle")
        } else {
            wall
        }
    }

    /// An empty `album` means something specific — there is nothing deeper —
    /// and saying "这个文件夹是空的" there would be a lie about a folder that is
    /// full of pictures.
    private var emptyTitle: String {
        switch store.view {
        case .album: "这底下没有更深的相册"
        case .explore, .image: "这个文件夹是空的"
        }
    }

    private var wall: some View {
        MasonryWall(
            items: store.entries,
            columnCount: columnBinding,
            columnRange: WallColumns.range,
            spacing: 4,
            aspectRatio: { $0.aspectRatio },
            onNearEnd: { Task { await store.loadMoreIfNeeded() } },
            scroll: scroll
        ) { entry, size in
            Button {
                // A pinch that starts on a cell has to resize the wall, not
                // open the cell — and SwiftUI fires a Button on the lift of
                // the still finger all the same. See MultiTouch.
                guard MultiTouch.shared.acceptsTap() else { return }
                open(entry)
            } label: {
                WallCell(entry: entry, size: size, imageURL: client.wallImageURL(for: entry))
            }
            .buttonStyle(.plain)
            // On the button itself, not inside its label — a Button absorbs the
            // accessibility of its content, which would hide the identifier.
            .accessibilityIdentifier(WallCell.identifier(for: entry))
        }
        .accessibilityIdentifier("masonry-wall")
    }

    private var columnBinding: Binding<Int> {
        Binding(get: { columns.count }, set: { columns.count = $0 })
    }

    // MARK: - Chrome

    private var topChrome: some View {
        TopChrome(
            title: store.displayName,
            crumbs: crumbs,
            isVisible: scroll.chromeVisible,
            showsBack: !store.path.isEmpty,
            onDrawer: { drawerOpen.toggle() },
            onBack: { dismiss() },
            onJump: { path in
                navigator.goToAncestor(path: path, hasChildren: treeStore.hasChildren(path))
            }
        )
    }

    /// The bottom edge has four tenants that must not stack up. The switcher
    /// and the paging counter are mutually exclusive by construction (one shows
    /// at rest and on the way up, the other only while scrolling down). The
    /// retry bar is the exception: a page failure has to stay visible and
    /// reachable, or the wall just silently stops growing and that is
    /// indistinguishable from having reached the end.
    @ViewBuilder
    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if let error = store.error, !store.entries.isEmpty {
                retryBar(error)
            } else if store.isLoading, !store.entries.isEmpty {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
            } else if scroll.counterVisible, let total = store.total, store.view.isPaged {
                Text("\(store.entries.count) / \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
            }

            ViewSwitcher(
                views: availableViews,
                current: store.view,
                isVisible: scroll.chromeVisible,
                onSelect: { store.view = $0 },
                onRandom: startRandom
            )
        }
        // No bottom padding here: the switcher carries its own, and doubling it
        // pushes the capsule visibly off the edge it is supposed to hug.
        .animation(.easeOut(duration: 0.25), value: scroll.counterVisible)
    }

    private func retryBar(_ error: GalleryError) -> some View {
        Button {
            Task { await store.retry() }
        } label: {
            Label(error.localizedDescription, systemImage: "arrow.clockwise")
                .font(.caption)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 16)
    }

    /// `album` and `explore` say nothing in a leaf folder — `album` comes back
    /// empty and `explore` shows exactly what `image` shows — so they are hidden
    /// there, as on the web.
    ///
    /// The test is exact and costs no request: the tree is already in memory and
    /// only contains directories whose subtree holds media, so "no children in
    /// the tree" *is* "album would be empty". See docs/adr/0007.
    private var availableViews: [FolderViewKind] {
        FolderViewKind.available(hasSubfolders: treeStore.hasChildren(store.path))
    }

    /// Root → … → here. Built from the path rather than from the navigation
    /// stack, because after a jump the stack holds one deep entry whose
    /// ancestors were never visited — and those ancestors are exactly what the
    /// user wants to reach.
    private var crumbs: [PathCrumb] {
        var result = [PathCrumb(name: "图库", path: "")]
        var prefix = ""
        for segment in store.path.split(separator: "/") {
            prefix = prefix.isEmpty ? String(segment) : prefix + "/" + segment
            result.append(PathCrumb(name: String(segment), path: prefix))
        }
        return result
    }

    // MARK: - Opening things

    private func open(_ entry: WallEntry) {
        switch entry {
        case .folder(let folder):
            navigator.open(folder: folder.path, from: store.view)
        case .media(let media):
            openViewer(at: media)
        }
    }

    /// The player's sequence is the wall's own order, which is what makes a
    /// single horizontal-swipe player enough for both images and videos.
    /// See docs/adr/0001.
    private func openViewer(at media: MediaItem) {
        let all = store.mediaEntries
        guard let index = all.firstIndex(of: media) else { return }
        let paged = store.view.isPaged
        presenter.present(
            items: all,
            startIndex: index,
            totalCount: paged ? store.total : nil,
            extend: paged
                ? { [store] in
                    await store.loadMoreIfNeeded()
                    return store.mediaEntries
                }
                : nil
        )
    }

    /// `random` is an action, not a view: the switcher does not stay on it, and
    /// closing the player puts the user back exactly where they were.
    ///
    /// The sequence is an unbounded sample stream from the backend, not a
    /// shuffle of what happens to be loaded — see docs/adr/0008.
    private func startRandom() {
        let stream = RandomStream(path: store.path, client: client)
        randomStream = stream
        Task {
            guard await stream.start() else { return }
            presenter.present(
                items: stream.items,
                startIndex: 0,
                unbounded: true,
                extend: {
                    await stream.extendIfNeeded()
                    return stream.items
                }
            )
        }
    }
}
