import SwiftUI

struct TableBlockView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]
    let alignments: [ColumnAlign]
    let theme: Theme

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        cell(header[column], column: column, isHeader: true)
                            // Set alignment on the first row only — Grid applies it to the whole column
                            .gridColumnAlignment(swiftUIAlignment(column))
                    }
                }
                .background(theme.codeBackground)

                ForEach(rows.indices, id: \.self) { row in
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(rows[row].indices, id: \.self) { column in
                            cell(rows[row][column], column: column, isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.rule, lineWidth: 1)
            }
            .padding(1)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func cell(_ text: AttributedString, column: Int, isHeader: Bool) -> some View {
        Text(text)
            .fontWeight(isHeader ? .semibold : .regular)
            .multilineTextAlignment(multiline(column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, theme.base * 0.7)
            .padding(.vertical, theme.base * 0.45)
            .frame(maxWidth: .infinity, alignment: frameAlignment(column))
    }

    private func align(_ column: Int) -> ColumnAlign {
        column < alignments.count ? alignments[column] : .leading
    }

    private func swiftUIAlignment(_ column: Int) -> HorizontalAlignment {
        switch align(column) {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ column: Int) -> Alignment {
        switch align(column) {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func multiline(_ column: Int) -> TextAlignment {
        switch align(column) {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
