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
    // Highlighting runs off the main thread and lands here once ready —
    // regex-scanning a near-cap file synchronously inside `body` would be a
    // real render-thread hitch (SyntaxHighlighter's own cap is a size bound,
    // not a speed guarantee).
    @State private var highlighted: AttributedString?

    /// Highlighting language inferred from the file extension; `.plain` for
    /// anything unrecognized (see SyntaxHighlighter's covered-languages note).
    private var language: SyntaxLanguage {
        SyntaxLanguage.detect(extension: (path as NSString).pathExtension)
    }

    var body: some View {
        ScrollView {
            if let highlighted {
                Text(highlighted)
                    .font(Theme.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            } else {
                ProgressView().padding(40)
            }
        }
        .navigationTitle((path as NSString).lastPathComponent)
        .inlineNavigationBarTitle()
        .task(id: path) { await loadAndHighlight() }
    }

    private func loadAndHighlight() async {
        highlighted = nil
        await store.loadFile(path: path, ref: ref)
        // Checked by PATH, not just cancellation: `store.openFile` is one
        // shared slot on the store, not scoped to this view. `.task(id:)`
        // cancellation is cooperative — a superseded task's own in-flight
        // `loadFile` call can still resolve later and overwrite that shared
        // slot with a DIFFERENT file's content after a newer task already
        // moved on. Trusting `store.openFile` here only if it still matches
        // the file this task is actually responsible for closes that gap
        // regardless of which task's network call happens to finish last.
        guard !Task.isCancelled, let file = store.openFile, file.path == path,
              let text = file.text else { return }
        let result = await Self.highlighted(text, language: language)
        // Re-checked after the highlight pass for the same reason: the
        // shared slot (and this task's own cancellation state) could have
        // changed again while the detached highlighting work was running.
        guard !Task.isCancelled, store.openFile?.path == path else { return }
        highlighted = result
    }

    private static func highlighted(_ text: String, language: SyntaxLanguage) async -> AttributedString {
        guard !text.isEmpty else { return AttributedString("(empty file)") }
        return await Task.detached(priority: .userInitiated) {
            SyntaxHighlighting.attributedString(for: text, language: language)
        }.value
    }
}
