import SwiftUI

struct EmptyStateView: View {
    let theme: Theme
    let isTargeted: Bool
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void

    var body: some View {
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
                Button("Open File…", action: onOpenFile)
                    .buttonStyle(.glassProminent)
                Button("Open Folder…", action: onOpenFolder)
                    .buttonStyle(.glass)
            }
            .padding(.top, theme.base * 0.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.18), value: isTargeted)
    }
}
