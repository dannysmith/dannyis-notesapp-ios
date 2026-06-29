import Foundation

/// Pure text helpers shared between the app and the Share Extension.
enum ShareFormatting {
    /// Prefixes each line with `> ` to form a markdown blockquote.
    static func blockquote(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
    }
}
