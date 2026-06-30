import SwiftUI
import UIKit

/// A plain-text markdown source editor backed by `UITextView`.
///
/// The `String` is the single source of truth — text is never parsed or
/// rewritten, so raw markdown and embedded MDX/JSX survive verbatim. A keyboard
/// accessory toolbar inserts markdown syntax around the current selection.
struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    /// Fills its container and scrolls internally (full-screen mode), rather
    /// than growing to fit (inline-in-a-Form mode).
    var isExpanded = false
    /// Becomes first responder when it appears (used by the full-screen cover).
    var autofocus = false
    /// When set, the toolbar shows an expand/collapse button that calls this.
    var onToggleExpand: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        // Source text: keep punctuation literal and predictable.
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        // Inline: grow to fit (no scroll) and wrap to the available width rather
        // than demanding the full single-line width. Expanded: fill and scroll.
        textView.isScrollEnabled = isExpanded
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.inputAccessoryView = context.coordinator.makeToolbar()
        textView.text = text
        context.coordinator.textView = textView
        MarkdownSyntaxHighlighter.highlight(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = textView
        // Only overwrite when the external value genuinely diverged, so we don't
        // stomp the cursor on every keystroke.
        if textView.text != text {
            textView.text = text
            MarkdownSyntaxHighlighter.highlight(textView)
        }
        if autofocus, !context.coordinator.didAutofocus {
            context.coordinator.didAutofocus = true
            textView.becomeFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: UITextView?
        var didAutofocus = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            // Skip while composing (IME marked text) to avoid disrupting input.
            guard textView.markedTextRange == nil else { return }
            MarkdownSyntaxHighlighter.highlight(textView)
        }

        // MARK: - Toolbar

        func makeToolbar() -> UIView {
            let bar = UIToolbar()
            bar.sizeToFit()
            var items: [UIBarButtonItem] = [
                button("bold", #selector(applyBold), "Bold"),
                button("italic", #selector(applyItalic), "Italic"),
                button("link", #selector(applyLink), "Link"),
                button("number", #selector(applyHeading), "Heading"),
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            ]
            if parent.onToggleExpand != nil {
                let symbol = parent.isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right"
                items.append(button(symbol, #selector(toggleExpand), parent.isExpanded ? "Collapse" : "Expand"))
            }
            items.append(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard)))
            bar.items = items

            // An inputAccessoryView sits flush against the top of the keyboard.
            // Host the bar in a slightly taller, transparent container with the
            // bar pinned to the top, so the gap at the bottom separates the
            // buttons from the keyboard.
            let barHeight = bar.frame.height
            let gap: CGFloat = 8
            let container = UIView(frame: CGRect(x: 0, y: 0, width: bar.frame.width, height: barHeight + gap))
            container.backgroundColor = .clear
            bar.frame = CGRect(x: 0, y: 0, width: bar.frame.width, height: barHeight)
            bar.autoresizingMask = [.flexibleWidth]
            container.addSubview(bar)
            return container
        }

        @objc private func toggleExpand() {
            parent.onToggleExpand?()
        }

        private func button(_ symbol: String, _ action: Selector, _ label: String) -> UIBarButtonItem {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
            item.accessibilityLabel = label
            return item
        }

        @objc private func dismissKeyboard() {
            textView?.resignFirstResponder()
        }

        // MARK: - Formatting actions

        @objc private func applyBold() {
            wrapSelection(prefix: "**", suffix: "**")
        }

        @objc private func applyItalic() {
            wrapSelection(prefix: "_", suffix: "_")
        }

        /// Wraps the selection in `prefix`/`suffix`. With no selection, inserts
        /// both markers and places the cursor between them.
        private func wrapSelection(prefix: String, suffix: String) {
            guard let textView, let range = textView.selectedTextRange else { return }
            let nsRange = textView.selectedRange
            let selected = (textView.text as NSString).substring(with: nsRange)
            textView.replace(range, withText: prefix + selected + suffix)

            let prefixLength = (prefix as NSString).length
            let location: Int = if selected.isEmpty {
                nsRange.location + prefixLength
            } else {
                nsRange.location + ((prefix + selected + suffix) as NSString).length
            }
            textView.selectedRange = NSRange(location: location, length: 0)
            parent.text = textView.text
        }

        /// Inserts `[text](url)`. Pre-fills the URL from the clipboard if it
        /// holds one, and selects whichever placeholder still needs filling in.
        @objc private func applyLink() {
            guard let textView, let range = textView.selectedTextRange else { return }
            let nsRange = textView.selectedRange
            let selected = (textView.text as NSString).substring(with: nsRange)

            let clipboardURL = UIPasteboard.general.hasURLs ? UIPasteboard.general.url?.absoluteString : nil
            let textPart = selected.isEmpty ? "text" : selected
            let urlPart = clipboardURL ?? "url"
            textView.replace(range, withText: "[\(textPart)](\(urlPart))")

            let base = nsRange.location
            let textLength = (textPart as NSString).length
            if selected.isEmpty {
                // Select the "text" placeholder (just after the opening bracket).
                textView.selectedRange = NSRange(location: base + 1, length: textLength)
            } else if clipboardURL == nil {
                // Select the "url" placeholder (after "](").
                textView.selectedRange = NSRange(location: base + 1 + textLength + 2, length: (urlPart as NSString).length)
            } else {
                let full = "[\(textPart)](\(urlPart))"
                textView.selectedRange = NSRange(location: base + (full as NSString).length, length: 0)
            }
            parent.text = textView.text
        }

        /// Cycles the current line's heading level: none → # → ## → ### → none.
        @objc private func applyHeading() {
            guard let textView else { return }
            let ns = textView.text as NSString
            let caret = min(textView.selectedRange.location, ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))

            var line = ns.substring(with: lineRange)
            var trailingNewline = ""
            if line.hasSuffix("\n") {
                trailingNewline = "\n"
                line.removeLast()
            }

            let (currentLevel, content) = strippedHeading(from: line)
            let newLevel = currentLevel >= 3 ? 0 : currentLevel + 1
            let prefix = newLevel > 0 ? String(repeating: "#", count: newLevel) + " " : ""
            let newLine = prefix + content + trailingNewline

            if let textRange = makeTextRange(in: textView, for: lineRange) {
                textView.replace(textRange, withText: newLine)
            }

            // Offset the *original* caret by the length change. Reading
            // `selectedRange` here instead would compound the shift, since
            // `replace` has already moved the selection to the line's new end.
            let delta = (newLine as NSString).length - lineRange.length
            let newCaret = max(lineRange.location, caret + delta)
            textView.selectedRange = NSRange(location: min(newCaret, (textView.text as NSString).length), length: 0)
            parent.text = textView.text
        }

        /// Converts an `NSRange` into a `UITextRange` for the text-editing APIs.
        private func makeTextRange(in textView: UITextView, for nsRange: NSRange) -> UITextRange? {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: nsRange.location),
                  let end = textView.position(from: start, offset: nsRange.length)
            else { return nil }
            return textView.textRange(from: start, to: end)
        }

        /// Splits a leading `#{1,6} ` heading marker off a line, returning the
        /// level (0 if none) and the remaining content.
        private func strippedHeading(from line: String) -> (level: Int, content: String) {
            var hashes = 0
            var index = line.startIndex
            while index < line.endIndex, line[index] == "#", hashes < 6 {
                hashes += 1
                index = line.index(after: index)
            }
            if hashes > 0, index < line.endIndex, line[index] == " " {
                return (hashes, String(line[line.index(after: index)...]))
            }
            return (0, line)
        }
    }
}
