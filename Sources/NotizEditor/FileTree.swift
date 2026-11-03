import CoreServices
import Foundation

/// A file or folder in the sidebar.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    let date: Date
    var children: [FileNode]?

    var id: URL { url }

    /// Notes are .txt files; their extension isn't shown, other extensions are.
    var displayName: String {
        isFolder || url.pathExtension.lowercased() != "txt" ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    var noteCount: Int {
        (children ?? []).reduce(0) { $0 + ($1.isFolder ? $1.noteCount : 1) }
    }

    /// Reads a folder with all subfolders. Hidden files and app bundles are left out.
    static func load(_ folder: URL, sortByDate: Bool) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                        options: [.skipsHiddenFiles]) else { return [] }
        let nodes = items.compactMap { url -> FileNode? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isPackage == true { return nil }
            let isFolder = values?.isDirectory == true
            let date = values?.contentModificationDate ?? .distantPast
            return FileNode(url: url.standardizedFileURL, isFolder: isFolder, date: date,
                            children: isFolder ? load(url, sortByDate: sortByDate) : nil)
        }
        return nodes.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            if sortByDate, !a.isFolder { return a.date > b.date }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
    }
}

/// Calls back (on the main queue) when anything inside a folder changes, also changes made in the Finder.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(_ folder: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// A hit of the sidebar search.
struct SearchResult: Identifiable, Hashable {
    let url: URL
    let snippet: String?
    var id: URL { url }
}

enum NoteSearch {
    /// Notes whose name or text contains all words of `query` (case and accents don't matter).
    static func run(_ query: String, in nodes: [FileNode]) -> [SearchResult] {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var results: [SearchResult] = []
        func visit(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isFolder { visit(node.children ?? []); continue }
                let name = node.displayName
                let text = readText(node.url)
                let all = name + "\n" + (text ?? "")
                guard words.allSatisfy({ all.range(of: $0, options: options) != nil }) else { continue }
                var snippet: String?
                if let text, let hit = text.range(of: words[0], options: options) {
                    let line = text.lineRange(for: hit)
                    snippet = text[line].trimmingCharacters(in: .whitespacesAndNewlines)
                    if snippet!.count > 120 {
                        let start = text.index(hit.lowerBound, offsetBy: -40, limitedBy: line.lowerBound) ?? line.lowerBound
                        snippet = "…" + String(text[start...].prefix(110)).trimmingCharacters(in: .newlines)
                    }
                }
                results.append(SearchResult(url: node.url, snippet: snippet))
            }
        }
        visit(nodes)
        return results
    }

    private static func readText(_ url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 4_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? TextFile.decode(data).string
    }
}
