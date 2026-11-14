import SwiftUI

struct EmptyStateView: View {
    let theme: Theme
    let isTargeted: Bool
    let recents: [RecentItem]
    let onNewNote: () -> Void
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onOpenRecent: (RecentItem) -> Void

    /// The window can be as short as 360pt — the full list lives in File ▸ Open Recent
    private static let shownRecents = 5

    var body: some View {
        // A short window drops the list rather than clipping the buttons — the menu still has it
        ViewThatFits(in: .vertical) {
            content(showsRecents: !recents.isEmpty)
            content(showsRecents: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.18), value: isTargeted)
    }

    private func content(showsRecents: Bool) -> some View {
        VStack(spacing: theme.base * 1.1) {
            Image(systemName: isTargeted ? "arrow.down.doc" : "doc.richtext")
                .font(.system(size: theme.base * 3.4, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))

            Text(isTargeted ? "Drop it here" : "Nothing open yet")
                .font(Fonts.body(family: theme.prose, size: theme.base * 1.25, weight: .semibold))

            Text("Drop a .md file — or a whole folder — right here")
                .font(theme.body)
                .foregroundStyle(.secondary)

            HStack(spacing: theme.base * 0.6) {
                Button("New Note", action: onNewNote)
                    .buttonStyle(.glass)
                Button("Open File…", action: onOpenFile)
                    .buttonStyle(.glassProminent)
                Button("Open Folder…", action: onOpenFolder)
                    .buttonStyle(.glass)
            }
            .padding(.top, theme.base * 0.3)

            if showsRecents {
                recentList
                    .padding(.top, theme.base * 0.8)
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            ForEach(recents.prefix(Self.shownRecents)) { item in
                RecentRow(item: item) { onOpenRecent(item) }
            }
        }
        .frame(maxWidth: 420)
    }
}

private struct RecentRow: View {
    let item: RecentItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(item.displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                isHovered ? Color.primary.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.url.path(percentEncoded: false))
    }
}
