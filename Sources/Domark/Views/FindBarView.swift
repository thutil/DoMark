import SwiftUI

/// The ⌘F bar that floats over the preview.
///
/// The editor pane has NSTextView's own find bar, so this one only ever covers the
/// rendered side — see `DomarkCommands.startFind()` for which of the two ⌘F reaches.
struct FindBarView: View {
    @Bindable var find: FindSession
    let theme: Theme

    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Find in document", text: $find.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .frame(width: 190)
                    .onSubmit { find.step(1) }

                if !find.query.isEmpty {
                    Button {
                        find.query = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }

                Text(status)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(hasNoMatch ? Color.red.opacity(0.8) : Color.secondary)
                    .frame(minWidth: 64, alignment: .trailing)

                Divider().frame(height: 16)

                Toggle(isOn: $find.isCaseSensitive) {
                    Image(systemName: "textformat")
                        .font(.system(size: 12))
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Match case")

                stepButton("chevron.up", delta: -1, help: "Previous match (⇧⌘G)")
                stepButton("chevron.down", delta: 1, help: "Next match (⌘G)")

                Button("Done") { find.dismiss() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.top, 12)
        // Esc closes the bar, the way every other macOS find bar behaves
        .onKeyPress(.escape) {
            find.dismiss()
            return .handled
        }
        .onAppear { isFocused = true }
        // ⌘F while the bar is already open should put the caret back in the field
        .onChange(of: find.focusToken) { isFocused = true }
    }

    private var hasNoMatch: Bool { !find.query.isEmpty && find.matchCount == 0 }

    private var status: String {
        if find.query.isEmpty { return "" }
        guard find.matchCount > 0 else { return "No results" }
        return "\(find.index + 1) of \(find.matchCount)"
    }

    private func stepButton(_ symbol: String, delta: Int, help: String) -> some View {
        Button {
            find.step(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18, height: 16)
        }
        .buttonStyle(.plain)
        .disabled(find.matchCount == 0)
        .help(help)
    }
}
