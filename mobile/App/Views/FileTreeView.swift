// File tree (flat, sorted) + file viewer with monospaced content.
import SwiftUI
import HyperGitCore

struct FileTreeView: View {
    @Environment(AppStore.self) private var store
    let branch: String?

    private var sorted: [HGFileEntry] {
        store.fileTree.sorted { lhs, rhs in
            (lhs.kind == .dir ? 0 : 1, lhs.path) < (rhs.kind == .dir ? 0 : 1, rhs.path)
        }
    }

    var body: some View {
        Group {
            if store.fileTree.isEmpty {
                PlaceholderView(icon: "folder", title: "No files",
                                subtitle: "Tree is fetched when the repo is opened.")
            } else {
                List(sorted) { entry in
                    NavigationLink {
                        FileViewerView(path: entry.path, ref: branch)
                    } label: {
                        Label(entry.name, systemImage: entry.kind == .dir ? "folder" : "doc.text")
                            .foregroundStyle(entry.kind == .dir ? .secondary : .primary)
                    }
                }
            }
        }
        .task { await store.loadFileTree(branch: branch) }
    }
}

struct FileViewerView: View {
    @Environment(AppStore.self) private var store
    let path: String
    let ref: String?
    var body: some View {
        ScrollView {
            if let text = store.openFile?.text {
                Text(text.isEmpty ? "(empty file)" : text)
                    .font(Theme.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            } else {
                ProgressView().padding(40)
            }
        }
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: path) { await store.loadFile(path: path, ref: ref) }
    }
}
