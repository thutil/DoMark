import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Set by an `align="center"` block, so the rows inside it can line up the same way
    @Entry var blockAlignment: HorizontalAlignment = .leading
}

/// `<details>`: the summary with a disclosure chevron, the content only once opened
struct DetailsBlockView: View {
    let summary: AttributedString
    let content: [RenderBlock]
    let theme: Theme

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.blockSpacing) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: theme.base * 0.45) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: theme.base * 0.7, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(summary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: theme.blockSpacing) {
                    ForEach(content.indices, id: \.self) { index in
                        BlockView(block: content[index], theme: theme).equatable()
                    }
                }
                .padding(.leading, theme.base * 1.15)
                .transition(.opacity)
            }
        }
    }
}

/// A logo or a line of badges: images at their own (or their tag's) size, wrapping onto
/// more lines when the column is too narrow
struct ImageRowView: View {
    let images: [SizedImage]
    let theme: Theme
    @Environment(\.blockAlignment) private var alignment

    var body: some View {
        FlowLayout(alignment: alignment, spacing: theme.base * 0.3) {
            ForEach(images.indices, id: \.self) { index in
                SizedImageView(image: images[index], maxWidth: theme.contentWidth, theme: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

private struct SizedImageView: View {
    let image: SizedImage
    let maxWidth: CGFloat
    let theme: Theme

    @State private var loaded: NSImage?
    @State private var failed = false

    init(image: SizedImage, maxWidth: CGFloat, theme: Theme) {
        self.image = image
        self.maxWidth = maxWidth
        self.theme = theme
        _loaded = State(initialValue: image.url.flatMap { ImageCache.shared.image(for: $0) })
    }

    var body: some View {
        Group {
            if let loaded {
                Image(nsImage: loaded)
                    .resizable()
                    .frame(width: size(of: loaded).width, height: size(of: loaded).height)
                    .help(image.alt)
            } else if failed || image.url == nil {
                Label(image.alt.isEmpty ? "Image" : image.alt, systemImage: "photo.badge.exclamationmark")
                    .font(theme.caption)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear.frame(width: image.width ?? 20, height: image.height ?? 20)
            }
        }
        .task(id: image.url) {
            guard let url = image.url, loaded == nil else { return }
            if let result = await ImageCache.shared.load(url) { loaded = result } else { failed = true }
        }
    }

    /// The tag's width and height win; one of them alone keeps the aspect ratio;
    /// never wider than the text column
    private func size(of nsImage: NSImage) -> CGSize {
        let natural = nsImage.size
        let aspect = natural.width > 0 ? natural.height / natural.width : 1
        var width = image.width ?? image.height.map { $0 / max(aspect, 0.0001) } ?? natural.width
        var height = image.height ?? width * aspect
        if width > maxWidth {
            height *= maxWidth / width
            width = maxWidth
        }
        return CGSize(width: width, height: height)
    }
}

/// Lays children out left to right, starting a new line when the next one does not fit
private struct FlowLayout: Layout {
    var alignment: HorizontalAlignment
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = switch alignment {
            case .center: bounds.minX + (bounds.width - row.width) / 2
            case .trailing: bounds.maxX - row.width
            default: bounds.minX
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
                rows[rows.count - 1].width = size.width
            } else {
                rows[rows.count - 1].width += extra
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
