import Foundation

struct FileNode: Identifiable, Hashable {
    let url: URL
    let name: String
    /// nil = a file, non-nil = a directory
    let children: [FileNode]?

    var id: URL { url }
    var isDirectory: Bool { children != nil }
}

enum FolderScanner {
    /// Always skipped: no markdown anyone wants to read, but big enough to slow the scan down
    static let ignored: Set<String> = [
        ".git", ".build", ".swiftpm", ".vscode", ".idea", ".cache", ".next", ".venv",
        "node_modules", "Pods", "DerivedData", "build", "dist", "out", "target",
        "vendor", "venv", "__pycache__",
    ]

    static let maxDepth = 6

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    struct Result {
        var tree: [FileNode]
        /// Every directory visited, **including ones with no markdown yet** — these get watched.
        /// Watching only what is in the tree would miss the first .md dropped into an empty folder.
        var directories: [URL]
    }

    /// Scans recursively and **prunes directories that contain no markdown**,
    /// otherwise the sidebar fills with empty folders and the files get lost in them.
    static func scan(_ folder: URL) -> Result {
        var directories: [URL] = [folder]
        let tree = walk(folder, depth: 0, directories: &directories)
        return Result(tree: tree, directories: directories)
    }

    private static func walk(_ folder: URL, depth: Int, directories: inout [URL]) -> [FileNode] {
        guard depth < maxDepth else { return [] }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        var subdirectories: [FileNode] = []
        var files: [FileNode] = []

        for url in contents {
            let name = url.lastPathComponent
            if isDirectory(url) {
                guard !ignored.contains(name) else { continue }
                directories.append(url)
                let children = walk(url, depth: depth + 1, directories: &directories)
                guard !children.isEmpty else { continue } // no markdown inside, so do not show it
                subdirectories.append(FileNode(url: url, name: name, children: children))
            } else if DocumentStore.isReadable(url) {
                files.append(FileNode(url: url, name: name, children: nil))
            }
        }

        let byName = { (a: FileNode, b: FileNode) in
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return subdirectories.sorted(by: byName) + files.sorted(by: byName)
    }

    /// Flattens the tree into sidebar order — used by ⌘[ / ⌘]
    static func flatten(_ nodes: [FileNode]) -> [URL] {
        nodes.flatMap { node in
            if let children = node.children { flatten(children) } else { [node.url] }
        }
    }
}
