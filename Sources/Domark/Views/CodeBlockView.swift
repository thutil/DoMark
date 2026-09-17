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
                ScrollView(.horizontal) { text }
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
