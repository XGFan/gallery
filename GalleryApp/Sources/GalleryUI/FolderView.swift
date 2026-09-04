import SwiftUI

/// A folder screen.
///
/// There is exactly one folder screen and one toggle on it — recursive on/off —
/// which together cover what the web frontend spread across three URL "modes".
/// See CONTEXT.md and the deprecated-terms table there.
struct FolderView: View {
    let client: GalleryClient
    @State private var store: FolderStore
    @State private var columnCount: Int
    @State private var viewer: ViewerContext?

    init(path: String, client: GalleryClient) {
        self.client = client
        _store = State(initialValue: FolderStore(path: path, client: client))
        _columnCount = State(initialValue: ColumnPreference.load())
    }

    var body: some View {
        content
            .navigationTitle(store.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
            .task { await store.loadInitial() }
            .fullScreenCoverCompat(item: $viewer) { context in
                ViewerView(
                    items: context.items,
                    startIndex: context.startIndex,
                    client: client,
                    onClose: { viewer = nil }
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.error, store.entries.isEmpty {
            ErrorStateView(error: error) {
                Task { await store.reload() }
            }
        } else if store.entries.isEmpty, store.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.entries.isEmpty {
            ContentUnavailableView("这个文件夹是空的", systemImage: "photo.on.rectangle")
        } else {
            wall
        }
    }

    private var wall: some View {
        MasonryWall(
            items: store.entries,
            columnCount: columnCount,
            spacing: 4,
            aspectRatio: { $0.aspectRatio },
            onNearEnd: { Task { await store.loadMoreIfNeeded() } }
        ) { entry, size in
            NavigationLinkOrButton(entry: entry) {
                open(entry)
            } label: {
                WallCell(entry: entry, size: size, imageURL: client.wallImageURL(for: entry))
            }
            // On the button itself, not inside its label — a Button absorbs the
            // accessibility of its content, which would hide the identifier.
            .accessibilityIdentifier(WallCell.identifier(for: entry))
        }
        .overlay(alignment: .bottom) { loadingFooter }
        .accessibilityIdentifier("masonry-wall")
    }

    @ViewBuilder
    private var loadingFooter: some View {
        // A page failure must stay visible and recoverable. Without this the
        // wall just stops growing: no spinner, no message, and scrolling does
        // nothing — indistinguishable from having reached the end.
        if let error = store.error, !store.entries.isEmpty {
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
            .padding(.bottom, 12)
            .padding(.horizontal, 16)
        } else if store.isLoading, !store.entries.isEmpty {
            ProgressView()
                .padding(8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
        } else if let total = store.total, store.recursive {
            Text("\(store.entries.count) / \(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                setColumns(columnCount + 1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(columnCount >= ColumnPreference.maxColumns)

            Button {
                setColumns(columnCount - 1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(columnCount <= ColumnPreference.minColumns)

            Toggle(isOn: $store.recursive) {
                Label("递归", systemImage: store.recursive ? "square.stack.3d.down.right.fill" : "square.stack.3d.down.right")
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("recursive-toggle")
        }
    }

    private func setColumns(_ value: Int) {
        let clamped = min(max(value, ColumnPreference.minColumns), ColumnPreference.maxColumns)
        columnCount = clamped
        ColumnPreference.store(clamped)
    }

    private func open(_ entry: WallEntry) {
        guard case .media = entry else { return }
        // The viewer's sequence is the wall's own order, which is what makes a
        // single horizontal-swipe player enough for both images and videos.
        // See docs/adr/0001.
        let media = store.entries.compactMap { entry -> MediaItem? in
            if case .media(let m) = entry { return m }
            return nil
        }
        guard case .media(let tapped) = entry,
              let index = media.firstIndex(of: tapped)
        else { return }
        viewer = ViewerContext(items: media, startIndex: index)
    }
}

struct ViewerContext: Identifiable, Hashable {
    let items: [MediaItem]
    let startIndex: Int
    var id: String { (items.indices.contains(startIndex) ? items[startIndex].path : "") + "@\(startIndex)" }
}

/// Folders push onto the navigation stack; media opens the viewer in place.
private struct NavigationLinkOrButton<Label: View>: View {
    let entry: WallEntry
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        switch entry {
        case .folder(let folder):
            NavigationLink(value: Route.folder(folder.path)) { label }
                .buttonStyle(.plain)
        case .media:
            Button(action: action) { label }
                .buttonStyle(.plain)
        }
    }
}

enum Route: Hashable {
    case folder(String)
}

enum ColumnPreference {
    static let minColumns = 1
    #if os(macOS)
    static let maxColumns = 8
    static let defaultColumns = 5
    #else
    static let maxColumns = 5
    static let defaultColumns = 2
    #endif

    private static let key = "wall.columns"

    static func load() -> Int {
        let stored = UserDefaults.standard.integer(forKey: key)
        guard stored >= minColumns, stored <= maxColumns else { return defaultColumns }
        return stored
    }

    static func store(_ value: Int) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

struct ErrorStateView: View {
    let error: GalleryError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("打不开图库", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("重试", action: retry)
        }
    }
}

extension View {
    /// `fullScreenCover` is iOS-only; macOS gets a sheet, which is the closest
    /// native equivalent for a modal viewer.
    @ViewBuilder
    func fullScreenCoverCompat<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}
