import SwiftUI

struct SidebarView: View {
    let tree: [FileNode]
    let folderName: String
    @Binding var selection: URL?

    var body: some View {
        Group {
            if tree.isEmpty {
                ContentUnavailableView(
                    "No Markdown Files",
                    systemImage: "folder",
                    description: Text("There are no .md files in this folder.")
                )
            } else {
                List(tree, children: \.children, selection: $selection) { node in
                    Label(node.name, systemImage: node.isDirectory ? "folder" : "document.badge.gearshape")
                        .lineLimit(1)
                        .help(node.url.path(percentEncoded: false))
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle(folderName)
        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
    }
}
