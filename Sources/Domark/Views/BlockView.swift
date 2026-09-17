import SwiftUI

struct BlockView: View, @MainActor Equatable {
    let block: RenderBlock
    let theme: Theme

    /// Lets SwiftUI skip whole rows instead of re-deriving them every frame
    nonisolated static func == (a: BlockView, b: BlockView) -> Bool {
        a.theme == b.theme && a.block == b.block
    }

    @ViewBuilder
    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(text)
                .lineSpacing(theme.headingLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? theme.base * 0.7 : theme.base * 0.25)

        case let .paragraph(text):
            Text(text)
                .lineSpacing(theme.paragraphLeading)
                .fixedSize(horizontal: false, vertical: true)

        case let .codeBlock(language, code, isWide):
            CodeBlockView(language: language, code: code, isWide: isWide, theme: theme)

        case let .quote(children):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.quoteBar)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                stack(children)
                    .padding(.leading, theme.base * 0.85)
            }
            .fixedSize(horizontal: false, vertical: true)

        case let .list(ordered, start, items):
            VStack(alignment: .leading, spacing: theme.listSpacing) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: theme.base * 0.45) {
                        marker(for: items[index], ordered: ordered, number: start + index)
                        stack(items[index].content, spacing: theme.listSpacing)
                    }
                }
            }
            .padding(.leading, theme.listIndent)

        case let .table(header, rows, alignments):
            TableBlockView(header: header, rows: rows, alignments: alignments, theme: theme)

        case .thematicBreak:
            Rectangle()
                .fill(theme.rule)
                .frame(height: 1)
                .padding(.vertical, theme.base * 0.6)

        case let .image(url, alt):
            ImageBlockView(url: url, alt: alt, theme: theme)
        }
    }

    @ViewBuilder
    private func stack(_ children: [RenderBlock], spacing: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: spacing ?? theme.blockSpacing) {
            ForEach(children.indices, id: \.self) { index in
                BlockView(block: children[index], theme: theme).equatable()
            }
        }
    }

    @ViewBuilder
    private func marker(for entry: ListEntry, ordered: Bool, number: Int) -> some View {
        Group {
            if let checked = entry.checked {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
            } else if ordered {
                Text("\(number).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("•")
                    .foregroundStyle(.secondary)
            }
        }
        .font(theme.body)
        .frame(width: theme.base * 1.3, alignment: .trailing)
    }
}
