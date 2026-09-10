import SwiftUI

struct RootView: View {
    private let client: GalleryClient

    @State private var navigator = Navigator()
    @State private var treeStore: TreeStore
    @State private var presenter = ViewerPresenter()
    /// One flag, two meanings, both "is the tree showing": an overlay drawer on
    /// iOS, the split view's sidebar column on macOS. The desktop starts with it
    /// open — a permanent sidebar is the point there.
    #if os(macOS)
    @State private var drawerOpen = true
    #else
    @State private var drawerOpen = false
    #endif

    /// How wide the iOS drawer is, and how far off-screen it parks.
    private static let drawerWidth: CGFloat = 288

    init() {
        let client = GalleryClient(baseURL: AppConfig.baseURL)
        self.client = client
        _treeStore = State(initialValue: TreeStore(client: client))
    }

    var body: some View {
        ZStack {
            shell

            #if os(macOS)
            // The player covers the *whole window*, sidebar included. It cannot
            // live inside the folder screen: that screen is the split view's
            // detail column, so an overlay it puts up would leave the tree
            // showing beside the picture. See docs/adr/0007.
            if let context = presenter.context {
                viewer(context)
                    .transition(.opacity)
                    .zIndex(10)
            }
            #endif
        }
        .environment(navigator)
        .environment(treeStore)
        .environment(presenter)
        #if os(macOS)
        .animation(.easeOut(duration: 0.18), value: presenter.context?.id)
        #else
        .fullScreenCover(item: viewerBinding) { context in
            viewer(context)
                // The player paints its own black. Clearing the cover's is what
                // lets the wall show through as a drag-to-dismiss fades it.
                .presentationBackground(.clear)
        }
        #endif
        #if os(iOS)
        // A zero-sized background purely to reach the window: what counts the
        // fingers is a recogniser installed there, so it sees every touch in
        // the app rather than only the ones a particular view is handed.
        .background { MultiTouchInstaller().frame(width: 0, height: 0) }
        #endif
        .task { await treeStore.load() }
    }

    // MARK: - Platform shell

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        // The sidebar is permanent on the desktop, so it needs no button to
        // reveal it — which is what let the toolbar go away entirely.
        NavigationSplitView(columnVisibility: splitVisibility) {
            treePanel
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            stack
        }
        // Process-level, not per-window: see WallColumns.installScrollZoom.
        .onAppear { WallColumns.installScrollZoom() }
        #else
        ZStack(alignment: .leading) {
            stack

            if drawerOpen {
                // Dimming the wall is what makes the drawer read as *over* the
                // content rather than beside it, and gives the tap target that
                // closes it.
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { drawerOpen = false }
                    .zIndex(1)
            }

            treePanel
                .frame(width: Self.drawerWidth)
                .background(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
                // Parked off-screen rather than conditionally built: the
                // sidebar keeps its level and its scroll position across
                // opens, and the slide has something to animate.
                .offset(x: drawerOpen ? 0 : -(Self.drawerWidth + 24))
                .shadow(color: .black.opacity(drawerOpen ? 0.4 : 0), radius: 16, x: 4)
                // Parked off-screen is still *present*, and a present drawer
                // stays in the accessibility tree: VoiceOver would swipe into a
                // tree nobody can see, and a UI test "finds" nodes at x = -260
                // that it then cannot tap.
                .accessibilityHidden(!drawerOpen)
                .zIndex(2)
        }
        .animation(.easeOut(duration: 0.28), value: drawerOpen)
        #endif
    }

    private var stack: some View {
        // Bound to an array rather than a NavigationPath because the tree needs
        // to know where the user is, and a NavigationPath will not say.
        NavigationStack(path: navigatorRoutes) {
            // Launch lands in `album` (docs/adr/0007). The root keeps its
            // own view from then on; a jump back to it is a pop, not an arrival.
            FolderView(
                path: "",
                view: .album,
                client: client,
                drawerOpen: $drawerOpen
            )
            .navigationDestination(for: Route.self) { route in
                FolderView(
                    path: route.path,
                    view: route.view,
                    client: client,
                    drawerOpen: $drawerOpen
                )
                // A sidebar jump replaces the whole stack, and `[A]` → `[B]`
                // keeps the same depth. Without an explicit identity SwiftUI
                // reuses the screen at that depth — `init` runs with B, but the
                // `@State` store inside was created for A and stays on A. The
                // sidebar highlighted B while the wall never moved.
                .id(route)
            }
        }
    }

    // MARK: - Tree

    @ViewBuilder
    private var treePanel: some View {
        if treeStore.tree != nil {
            FolderTreeView(
                selectedPath: navigator.currentPath,
                childrenOf: { treeStore.children(of: $0) },
                onSelect: { path in
                    navigator.jump(to: path, hasChildren: treeStore.hasChildren(path))
                    #if os(iOS)
                    // The drawer covers the wall, so it has to get out of the
                    // way once it has been used. macOS's sidebar is permanent —
                    // closing it there would collapse the column on every click.
                    drawerOpen = false
                    #endif
                }
            )
        } else if let error = treeStore.error {
            ErrorStateView(error: error) {
                Task { await treeStore.load() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Viewer

    private func viewer(_ context: ViewerContext) -> some View {
        ViewerView(
            items: context.items,
            startIndex: context.startIndex,
            client: client,
            onClose: { presenter.dismiss() },
            onNearEnd: { Task { await presenter.requestMore() } },
            totalCount: context.totalCount,
            unbounded: context.unbounded
        )
    }

    private var viewerBinding: Binding<ViewerContext?> {
        Binding(
            get: { presenter.context },
            set: { if $0 == nil { presenter.dismiss() } }
        )
    }

    #if os(macOS)
    private var splitVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { drawerOpen ? .all : .detailOnly },
            set: { drawerOpen = $0 != .detailOnly }
        )
    }
    #endif

    private var navigatorRoutes: Binding<[Route]> {
        Binding(
            get: { navigator.routes },
            set: { navigator.routes = $0 }
        )
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
