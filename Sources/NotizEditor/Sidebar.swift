import AppKit
import SwiftUI

/// The left side: the notes folder with its subfolders, other opened files, and the search.
struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        List(selection: $model.selection) {
            if model.search.isEmpty {
                Section {
                    NodeRows(nodes: model.tree)
                    if model.tree.isEmpty {
                        Text(L("No notes yet")).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(model.root.lastPathComponent)
                }
                if !model.otherFiles.isEmpty {
                    Section(L("Other Files")) {
                        ForEach(model.otherFiles, id: \.self) { url in
                            OtherFileRow(url: url)
                                .tag(url)
                        }
                    }
                }
            } else {
                Section(model.searchResults.isEmpty ? L("Nothing found") :
                            model.searchResults.count == 1 ? L("1 note found") : L("%d notes found", model.searchResults.count)) {
                    ForEach(model.searchResults) { result in
                        SearchRow(result: result, root: model.root)
                            .tag(result.url)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.search, placement: .sidebar, prompt: L("Search notes"))
        .onChange(of: model.selection) { _, url in
            if let url, !model.search.isEmpty, model.searchResults.contains(where: { $0.url == url }) {
                model.openSearchResult(url)
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if let url = urls.first {
                ItemMenu(url: url)
            } else {
                Button(L("New Note")) { model.newNote(in: model.root) }
                Button(L("New Folder")) { model.newFolder(in: model.root) }
            }
        }
        .onDeleteCommand {
            if let selection = model.selection, model.isInsideRoot(selection), model.renaming == nil { model.trash(selection) }
        }
        .dropDestination(for: URL.self) { urls, _ in model.drop(urls, into: model.root) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Menu {
                    Button(L("New Note")) { model.newNote() }
                    Button(L("New Folder")) { model.newFolder() }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("New note or folder"))
                Spacer()
                Menu {
                    Picker(L("Sort by"), selection: Binding(get: { settings.sortByDate }, set: { _ in model.toggleSort() })) {
                        Text(L("Name")).tag(false)
                        Text(L("Date Changed")).tag(true)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button(L("Show Notes Folder in Finder")) { model.reveal(model.root) }
                    Button(L("Choose Notes Folder …")) { model.chooseNotesFolder() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Sort and notes folder"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

/// A folder level: folders (open and closed) and notes.
private struct NodeRows: View {
    @EnvironmentObject private var model: AppModel
    let nodes: [FileNode]

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                DisclosureGroup(isExpanded: Binding(
                    get: { model.expanded.contains(node.url) },
                    set: { open in if open { model.expanded.insert(node.url) } else { model.expanded.remove(node.url) } }
                )) {
                    NodeRows(nodes: node.children ?? [])
                } label: {
                    NodeLabel(node: node)
                }
                .tag(node.url)
            } else {
                NodeLabel(node: node)
                    .tag(node.url)
            }
        }
    }
}

private struct NodeLabel: View {
    @EnvironmentObject private var model: AppModel
    let node: FileNode
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if model.renaming == node.url {
                RenameField(node: node)
            } else {
                Label {
                    Text(node.displayName).lineLimit(1)
                } icon: {
                    Image(systemName: icon)
                }
                .badge(node.isFolder && node.noteCount > 0 ? Text("\(node.noteCount)") : nil)
            }
        }
        .draggable(node.url)
        .dropDestination(for: URL.self) { urls, _ in
            guard node.isFolder else { return false }
            return model.drop(urls, into: node.url)
        } isTargeted: { dropTargeted = node.isFolder && $0 }
        .listRowBackground(dropTargeted ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.25)) : nil)
    }

    private var icon: String {
        if node.isFolder { return "folder" }
        switch node.url.pathExtension.lowercased() {
        case "txt", "text", "": return "doc.text"
        case "md", "markdown": return "text.badge.star"
        case "csv", "tsv": return "tablecells"
        case "log": return "list.bullet.rectangle"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Typing a new name right in the list (after "New Note", "New Folder" or "Rename").
private struct RenameField: View {
    @EnvironmentObject private var model: AppModel
    let node: FileNode
    @State private var name: String
    @FocusState private var focused: Bool

    init(node: FileNode) {
        self.node = node
        _name = State(initialValue: node.displayName)
    }

    var body: some View {
        TextField(L("Name"), text: $name)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { DispatchQueue.main.async { focused = true } }
            .onSubmit { model.rename(node.url, to: name) }
            .onExitCommand { model.renaming = nil }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, model.renaming == node.url { model.rename(node.url, to: name) }
            }
    }
}

private struct OtherFileRow: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    @State private var hovering = false

    var body: some View {
        HStack {
            Label(url.lastPathComponent, systemImage: "doc")
                .lineLimit(1)
                .help((url.path as NSString).abbreviatingWithTildeInPath)
            Spacer()
            if hovering {
                Button { model.closeOtherFile(url) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(L("Remove from the list"))
            }
        }
        .onHover { hovering = $0 }
    }
}

private struct SearchRow: View {
    let result: SearchResult
    let root: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.url.pathExtension.lowercased() == "txt" ? result.url.deletingPathExtension().lastPathComponent : result.url.lastPathComponent)
                .lineLimit(1)
            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            let folder = result.url.deletingLastPathComponent().path
            if folder.count > root.path.count {
                Text(String(folder.dropFirst(root.path.count + 1))).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Right-click menu of a note or folder.
struct ItemMenu: View {
    @EnvironmentObject private var model: AppModel
    let url: URL

    var body: some View {
        let inside = model.isInsideRoot(url)
        let isFolder = AppModel.isFolder(url)
        Button(L("New Note")) { model.newNote(in: isFolder ? url : url.deletingLastPathComponent()) }
            .disabled(!inside)
        Button(L("New Folder")) { model.newFolder(in: isFolder ? url : url.deletingLastPathComponent()) }
            .disabled(!inside)
        Divider()
        Button(L("Rename")) { model.renaming = url }
            .disabled(!inside)
        Button(L("Duplicate")) { model.duplicate(url) }
            .disabled(!inside || isFolder)
        Button(L("Show in Finder")) { model.reveal(url) }
        Button(L("Copy Path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
        Divider()
        if inside {
            Button(L("Move to Trash")) { model.trash(url) }
        } else {
            Button(L("Remove from the list")) { model.closeOtherFile(url) }
        }
    }
}
