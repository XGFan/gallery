import SwiftUI

struct RootView: View {
    private let client = GalleryClient(baseURL: AppConfig.baseURL)

    @State private var navigation = NavigationPath()
    @State private var tree: FolderTree?
    @State private var treeError: GalleryError?
    @State private var showsTree = false

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            treeContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            stack
        }
        .toolbar {
            ToolbarItem {
                Button {
                    FloatingWindowController.toggle(client: client)
                } label: {
                    Image(systemName: "pip")
                }
                .help("悬浮窗")
                .accessibilityIdentifier("floating-toggle")
            }
        }
        .task { await loadTree() }
        #else
        stack
            .sheet(isPresented: $showsTree) {
                NavigationStack {
                    treeContent
                        .navigationTitle("文件夹")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showsTree = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .task { await loadTree() }
        #endif
    }

    private var stack: some View {
        NavigationStack(path: $navigation) {
            FolderView(path: "", client: client)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .folder(let path):
                        FolderView(path: path, client: client)
                    }
                }
                #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsTree = true
                        } label: {
                            Image(systemName: "sidebar.leading")
                        }
                    }
                }
                #endif
        }
    }

    @ViewBuilder
    private var treeContent: some View {
        if let tree {
            List(tree.root.children, children: \.optionalChildren) { node in
                Button {
                    jump(to: node.path)
                } label: {
                    Label(node.name, systemImage: node.isLeaf ? "folder" : "folder.fill")
                }
                .buttonStyle(.plain)
            }
        } else if let treeError {
            ErrorStateView(error: treeError) {
                Task { await loadTree() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Jumping to an arbitrary folder is the whole point of keeping the tree —
    /// it saves popping back up and drilling down again. The stack is reset to a
    /// single entry so Back returns to the root rather than replaying the jump.
    private func jump(to path: String) {
        navigation = NavigationPath()
        if !path.isEmpty {
            navigation.append(Route.folder(path))
        }
        showsTree = false
    }

    private func loadTree() async {
        guard tree == nil else { return }
        do {
            tree = try await client.tree()
            treeError = nil
        } catch let error as GalleryError {
            treeError = error
        } catch {
            treeError = .badResponse
        }
    }
}
