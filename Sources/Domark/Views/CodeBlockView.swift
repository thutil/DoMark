import AppKit
import SwiftUI

struct CodeBlockView: View {
    let language: String?
    let code: AttributedString
    let isWide: Bool
    let theme: Theme

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        Group {
            // A nested ScrollView per code block is expensive to keep alive while the page
            // scrolls, so only the blocks that actually overflow get one.
            if isWide {
                // Room past the end of the longest line, so scrolling all the way brings
                // its last characters out from under the badge
                ScrollView(.horizontal) { text.padding(.trailing, theme.base * 4) }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            } else {
                text
            }
        }
        .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) { badge }
        .onHover { isHovering = $0 }
    }

    private var text: some View {
        Text(code)
            .font(theme.mono)
            .textSelection(.enabled)
            .padding(.horizontal, theme.base)
            .padding(.vertical, theme.base * 0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var badge: some View {
        HStack(spacing: theme.base * 0.4) {
            if let language, !isHovering {
                Text(language)
                    .font(theme.caption)
                    .foregroundStyle(.secondary)
            }
            if isHovering {
                Button {
                    copy()
                } label: {
                    Label(didCopy ? "Copied" : "Copy",
                          systemImage: didCopy ? "checkmark" : "document.on.document")
                        .font(theme.caption)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopy ? Color.accentColor : Color.secondary)
            }
        }
        .padding(.horizontal, theme.base * 0.6)
        .padding(.vertical, theme.base * 0.3)
        // Opaque, in the block's own tint: a long line runs underneath the badge, and a
        // see-through one left the two sets of letters printed on top of each other
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.codeBackground)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(theme.base * 0.3)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(code.characters), forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}
