import CryptoKit
import Foundation

/// Parsed result of reading a note file pulled from the repo.
struct ParsedFrontmatter {
    var title: String = ""
    var sourceURL: String?
    var customSlug: String?
    var draft: Bool = false
    var description: String?
    var pubDate: Date?
    var tags: [String] = []
    var styleguide: Bool = false
    var body: String = ""
}

/// Serializes notes to/from the YAML-frontmatter + markdown format the Astro
/// site expects. Notes are in `.prettierignore`, so output only needs to be
/// valid for the zod schema, not prettier-formatted.
///
/// The parser is deliberately minimal: it handles the flat, single-line fields
/// this app emits plus the common shapes in existing notes. It does not parse
/// arbitrary YAML (block scalars, nested maps, etc.).
enum FrontmatterSerializer {
    // MARK: - Hashing

    /// Stable SHA-256 hex digest of a string. Used to compare a note's current
    /// content against its last-synced baseline across launches.
    static func contentHash(of content: String) -> String {
        SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Dates & slugs

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        dateFormatter.date(from: string.trimmingCharacters(in: .whitespaces))
    }

    /// Common English filler words dropped from generated slugs.
    private static let fillerWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "for",
        "with", "at", "by", "from", "as", "is", "are", "was", "were", "be",
        "this", "that", "these", "those", "it", "its", "into", "about", "via"
    ]

    /// Generates a URL slug from a title: lowercased, filler words removed,
    /// non-alphanumerics collapsed to hyphens, and capped in length. Used both
    /// to pre-fill the custom slug field and to derive a note's filename.
    static func slug(from title: String, maxWords: Int = 8, maxLength: Int = 60) -> String {
        let words = title.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
        var kept = words.filter { !fillerWords.contains($0) }
        // If the title is entirely filler, fall back to the raw words.
        if kept.isEmpty { kept = words }
        kept = Array(kept.prefix(maxWords))

        var slug = kept.joined(separator: "-")
        if slug.count > maxLength {
            slug = String(slug.prefix(maxLength))
            // Avoid leaving a dangling partial word after truncation.
            if let lastHyphen = slug.lastIndex(of: "-") {
                slug = String(slug[..<lastHyphen])
            }
        }
        return slug.isEmpty ? "untitled" : slug
    }

    // MARK: - Serialize

    static func serialize(_ note: Note) -> String {
        var lines = ["---"]
        lines.append("title: \(yamlString(note.title))")
        if let url = note.sourceURL, !url.isEmpty {
            lines.append("sourceURL: \(url)")
        }
        if let slug = note.customSlug, !slug.isEmpty {
            lines.append("slug: \(slug)")
        }
        if note.draftFlag {
            lines.append("draft: true")
        }
        if let desc = note.noteDescription, !desc.isEmpty {
            lines.append("description: \(yamlString(desc))")
        }
        lines.append("pubDate: \(dateString(note.pubDate))")
        if !note.tags.isEmpty {
            let joined = note.tags.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("tags: [\(joined)]")
        }
        lines.append("---")
        lines.append("")
        let frontmatter = lines.joined(separator: "\n")
        let body = note.body.hasSuffix("\n") ? note.body : note.body + "\n"
        return frontmatter + "\n" + body
    }

    /// Double-quote and escape a YAML scalar. Safe for arbitrary titles.
    private static func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Parse

    static func parse(_ markdown: String) -> ParsedFrontmatter {
        var result = ParsedFrontmatter()
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")

        guard normalized.hasPrefix("---\n") else {
            result.body = normalized
            return result
        }
        let afterOpen = normalized.dropFirst(4)
        guard let closeRange = afterOpen.range(of: "\n---") else {
            result.body = normalized
            return result
        }

        let yaml = String(afterOpen[..<closeRange.lowerBound])
        var body = String(afterOpen[closeRange.upperBound...])
        if body.hasPrefix("\n") { body.removeFirst() }
        result.body = body

        let fields = yamlFields(from: yaml)
        result.title = fields["title"].map(unquote) ?? ""
        result.sourceURL = fields["sourceURL"].map(unquote)
        result.customSlug = fields["slug"].map(unquote)
        result.draft = fields["draft"] == "true"
        result.description = fields["description"].map(unquote)
        result.pubDate = fields["pubDate"].flatMap(date(from:))
        result.tags = fields["tags"].map(parseTags) ?? []
        result.styleguide = fields["styleguide"] == "true"
        return result
    }

    /// Splits flat `key: value` YAML lines into a dictionary. Ignores anything
    /// that isn't a simple single-line key/value pair.
    private static func yamlFields(from yaml: String) -> [String: String] {
        var fields: [String: String] = [:]
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        return fields
    }

    private static func unquote(_ value: String) -> String {
        var v = value
        let isQuoted = v.count >= 2 &&
            ((v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")))
        if isQuoted {
            v = String(v.dropFirst().dropLast())
        }
        return v
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseTags(_ value: String) -> [String] {
        var v = value
        if v.hasPrefix("[") { v.removeFirst() }
        if v.hasSuffix("]") { v.removeLast() }
        return v.split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }
}
