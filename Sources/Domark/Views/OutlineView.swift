import SwiftUI

/// The outline inspector: H1–H3, the one being read highlighted.
///
/// Rows are plain buttons, not a List selection — the highlight follows scrolling, and a
/// selection binding would turn every scroll into a jump.
struct OutlineView: View {
    let outline: Outline
    let current: Outline.Item.ID?
    let onSelect: (Outline.Item) -> Void

    var body: some View {
        Group {
            if outline.items.isEmpty {
                ContentUnavailableView("No Headings", systemImage: "list.bullet.indent")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            if let title = outline.title {
                                Text(title)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 6)
                            }
                            ForEach(outline.items) { item in
                                row(item)
                                    .id(item.id)
                            }
                        }
                        .padding(10)
                    }
                    // Keep the highlighted row on screen while the page scrolls past many headings
                    .onChange(of: current) {
                        guard let current else { return }
                        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(current) }
                    }
                }
            }
        }
        .inspectorColumnWidth(min: 180, ideal: 240, max: 380)
    }

    private func row(_ item: Outline.Item) -> some View {
        let isCurrent = item.id == current
        return Button { onSelect(item) } label: {
            Text(item.title)
                .font(.system(size: 12, weight: item.depth == 0 ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.primary : item.depth == 0 ? Color.primary : Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.leading, CGFloat(item.depth) * 12)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isCurrent ? Color.accentColor.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }
}
