import SwiftUI

/// Which block is at the top of the preview — written on every scroll, read only by the outline.
///
/// A class, not `@State` in ContentView: there every scroll re-ran the whole window's body
/// (sidebar, toolbar, every block row) just to move one highlight in the outline.
@MainActor
@Observable
final class ReadingPosition {
    var topBlockID: Int?
}

/// The rendered page.
///
/// Its own view so that state only the page cares about stays out of ContentView.
struct PreviewPane: View {
    let blocks: [IdentifiedBlock]
    let theme: Theme
    let isSplit: Bool
    let isTargeted: Bool
    let position: ReadingPosition
    @Binding var outlineJump: Int?

    @Environment(DocumentStore.self) private var store
    @Environment(FindSession.self) private var find

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.blockSpacing) {
                    ForEach(blocks) { item in
                        PageBlockView(item: item, theme: theme)
                            .equatable()
                            .id(item.id) // the anchor the find bar scrolls to
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: theme.contentWidth, alignment: .leading)
                .padding(.horizontal, isSplit ? theme.base * 1.6 : theme.pagePadding)
                .padding(.vertical, theme.pagePadding)
                .frame(maxWidth: .infinity) // centre the column in the window
            }
            // A new file should start at the top, not inherit the previous file's scroll offset
            .id(store.url)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { visible in
                // Only the outline observes this, so when it's closed the write re-renders nothing
                let top = visible.min()
                if position.topBlockID != top { position.topBlockID = top }
            }
            .onChange(of: outlineJump) {
                guard let outlineJump else { return }
                reveal(outlineJump, with: proxy, anchor: .top)
                self.outlineJump = nil // so picking the same heading again still fires
            }
            // Both are needed: stepping onto a hit in another block changes the id, while
            // stepping between two hits inside the same block only changes the index.
            .onChange(of: find.currentBlockID) { reveal(find.currentBlockID, with: proxy) }
            .onChange(of: find.index) { reveal(find.currentBlockID, with: proxy) }
            .environment(\.openURL, OpenURLAction { url in
                guard let target = Anchor.target(of: url) else { return .systemAction }
                if let id = Anchor.block(for: target, in: store.anchors) {
                    reveal(id, with: proxy, anchor: .top)
                }
                // A link to a heading that is not there does nothing — it must never
                // escape to the browser as a made-up URL
                return .handled
            })
        }
        .textSelection(.enabled)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) {
            if find.isPresented {
                FindBarView(find: find, theme: theme)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: isTargeted)
        .animation(.snappy(duration: 0.2), value: find.isPresented)
    }

    /// Find lands a match in the middle of the page; a heading belongs at the top of it
    private func reveal(_ blockID: Int?, with proxy: ScrollViewProxy, anchor: UnitPoint = .center) {
        guard let blockID else { return }
        withAnimation(.snappy(duration: 0.25)) {
            proxy.scrollTo(blockID, anchor: anchor)
        }
    }
}

/// A top-level block row. Compares by fingerprint, not content: deep-comparing every
/// AttributedString on the page each time the list re-evaluated cost O(document) per update.
private struct PageBlockView: View, @MainActor Equatable {
    let item: IdentifiedBlock
    let theme: Theme

    nonisolated static func == (a: PageBlockView, b: PageBlockView) -> Bool {
        a.item == b.item && a.theme == b.theme
    }

    var body: some View {
        BlockView(block: item.block, theme: theme)
    }
}

/// The outline, reading the scroll position itself so only it re-renders as the page scrolls
struct OutlinePanel: View {
    let outline: Outline
    let position: ReadingPosition
    let onSelect: (Outline.Item) -> Void

    var body: some View {
        OutlineView(
            outline: outline,
            current: outline.current(topBlockID: position.topBlockID),
            onSelect: onSelect
        )
    }
}
