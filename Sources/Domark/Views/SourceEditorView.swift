import AppKit
import SwiftUI

/// The markdown editing pane.
///
/// Wraps NSTextView by hand instead of using SwiftUI's `TextEditor` because every smart
/// substitution has to be turned off: macOS would otherwise turn `"` into `"` and `--` into `—`
/// on its own, silently breaking code blocks and markdown — and SwiftUI exposes no way to disable it.
struct SourceEditorView: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // This block is the whole reason NSTextView is used here
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 16)
        textView.string = text
        apply(theme, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only assign when the text really differs, otherwise the caret jumps to the start on every keystroke
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selected.location, (text as NSString).length),
                length: 0
            ))
        }
        apply(theme, to: textView)
    }

    private func apply(_ theme: Theme, to textView: NSTextView) {
        let font = Fonts.nsMono(family: theme.code, size: theme.base * 0.95)
        guard textView.font != font else { return }
        textView.font = font
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Puts the dot in the window's close button while there are unsaved changes (the macOS convention)
struct DocumentEditedMarker: NSViewRepresentable {
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let isEdited = isEdited
        DispatchQueue.main.async { view.window?.isDocumentEdited = isEdited }
    }
}
