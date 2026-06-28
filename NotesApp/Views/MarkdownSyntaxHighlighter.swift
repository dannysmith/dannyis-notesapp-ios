import UIKit

/// Applies overlay-only syntax highlighting to a markdown source `UITextView`.
///
/// Only visual attributes (font traits, colour, background) are changed — the
/// characters are never modified, so the literal markdown/MDX is preserved. The
/// whole document is restyled on each call; notes are short, so this is cheap.
enum MarkdownSyntaxHighlighter {
    private static let dim = UIColor.secondaryLabel
    private static let codeBackground = UIColor.secondarySystemFill

    static func highlight(_ textView: UITextView) {
        let storage = textView.textStorage
        let base = UIFont.preferredFont(forTextStyle: .body)
        let full = NSRange(location: 0, length: (storage.string as NSString).length)

        // Re-applied with the base attributes so rewriting the storage never
        // drops normal word wrapping.
        let wrapping = NSMutableParagraphStyle()
        wrapping.lineBreakMode = .byWordWrapping

        storage.beginEditing()
        storage.setAttributes(
            [.font: base, .foregroundColor: UIColor.label, .paragraphStyle: wrapping],
            range: full
        )
        styleBlocks(storage, base: base, full: full)
        styleEmphasis(storage, base: base, full: full)
        styleLinks(storage, full: full)
        styleCode(storage, base: base, full: full) // last, so code interiors win
        storage.endEditing()

        textView.typingAttributes = [.font: base, .foregroundColor: UIColor.label]
    }

    // MARK: - Block-level

    private static func styleBlocks(_ storage: NSTextStorage, base: UIFont, full: NSRange) {
        // Headings: whole line bold (same size), the # markers dimmed.
        headingRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            addTrait(.traitBold, to: match.range, in: storage, base: base)
            storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: 1))
        }
        // Blockquotes: whole line dimmed and italic.
        quoteRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            addTrait(.traitItalic, to: match.range, in: storage, base: base)
            storage.addAttribute(.foregroundColor, value: dim, range: match.range)
        }
        // Lists: the bullet / number marker dimmed.
        listRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: 1))
        }
    }

    // MARK: - Inline emphasis

    private static func styleEmphasis(_ storage: NSTextStorage, base: UIFont, full: NSRange) {
        boldRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            addTrait(.traitBold, to: match.range, in: storage, base: base)
            dimMarkers(match.range, width: 2, in: storage)
        }
        for regex in [italicUnderscoreRegex, italicStarRegex] {
            regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
                guard let match else { return }
                addTrait(.traitItalic, to: match.range, in: storage, base: base)
                dimMarkers(match.range, width: 1, in: storage)
            }
        }
    }

    // MARK: - Links

    private static func styleLinks(_ storage: NSTextStorage, full: NSRange) {
        linkRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            // Dim the brackets, parens and URL; keep the link text normal.
            storage.addAttribute(.foregroundColor, value: dim, range: match.range)
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: match.range(at: 1))
        }
    }

    // MARK: - Code

    private static func styleCode(_ storage: NSTextStorage, base: UIFont, full: NSRange) {
        let mono = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
        func applyCode(_ range: NSRange) {
            storage.addAttribute(.font, value: mono, range: range)
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: range)
            storage.addAttribute(.backgroundColor, value: codeBackground, range: range)
        }
        fencedCodeRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            applyCode(match.range)
        }
        inlineCodeRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            applyCode(match.range)
            dimMarkers(match.range, width: 1, in: storage)
        }
    }

    // MARK: - Helpers

    /// Merges a symbolic trait into whatever font already covers `range`, so
    /// e.g. bold inside a heading stays bold and bold+italic combine.
    private static func addTrait(
        _ trait: UIFontDescriptor.SymbolicTraits,
        to range: NSRange,
        in storage: NSTextStorage,
        base: UIFont
    ) {
        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let current = (value as? UIFont) ?? base
            let traits = current.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = current.fontDescriptor.withSymbolicTraits(traits) {
                storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: current.pointSize), range: subRange)
            }
        }
    }

    private static func dimMarkers(_ range: NSRange, width: Int, in storage: NSTextStorage) {
        let open = NSRange(location: range.location, length: width)
        let close = NSRange(location: range.location + range.length - width, length: width)
        storage.addAttribute(.foregroundColor, value: dim, range: open)
        storage.addAttribute(.foregroundColor, value: dim, range: close)
    }

    // MARK: - Patterns

    private static func compile(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are compile-time constants, so failure is a programmer error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let headingRegex = compile("^(#{1,6})\\s+.*$", .anchorsMatchLines)
    private static let quoteRegex = compile("^>+\\s?.*$", .anchorsMatchLines)
    private static let listRegex = compile("^\\s*([-*+]|\\d+\\.)\\s+", .anchorsMatchLines)
    private static let boldRegex = compile("\\*\\*(.+?)\\*\\*")
    private static let italicUnderscoreRegex = compile("(?<![A-Za-z0-9_])_(?=\\S)(.+?)(?<=\\S)_(?![A-Za-z0-9_])")
    private static let italicStarRegex = compile("(?<!\\*)\\*(?!\\*)(?=\\S)(.+?)(?<=\\S)\\*(?!\\*)")
    private static let linkRegex = compile("\\[([^\\]]*)\\]\\(([^)]*)\\)")
    private static let inlineCodeRegex = compile("`([^`\\n]+)`")
    private static let fencedCodeRegex = compile("^```[^\\n]*\\n[\\s\\S]*?\\n```$", .anchorsMatchLines)
}
