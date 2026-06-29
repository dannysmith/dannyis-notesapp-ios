import Foundation

/// Open Graph / Twitter card metadata for a URL — a Swift port of the site's
/// `fetchLinkMetadata.ts`, so previews match how `BookmarkCard.astro` renders.
struct LinkMetadata {
    let url: String
    let domain: String
    let title: String
    let description: String?
    let imageURL: URL?
}

/// Fetches and parses link metadata. Degrades gracefully: any failure (bad URL,
/// no network, non-200, missing tags) resolves to `nil` and the UI falls back.
enum LinkMetadataService {
    private static let cache = MetadataCache()

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    static func fetch(_ urlString: String) async -> LinkMetadata? {
        guard let url = URL(string: urlString), url.host != nil else { return nil }
        if let cached = await cache.get(urlString) { return cached }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { return nil }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  !html.isEmpty else { return nil }

            let metadata = parse(html: html, url: url)
            await cache.set(urlString, metadata)
            return metadata
        } catch {
            return nil
        }
    }

    // MARK: - Parsing

    /// Pure extraction of metadata from HTML — no networking, so it's unit-testable.
    static func parse(html: String, url: URL) -> LinkMetadata {
        let host = url.host ?? ""
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let title = extractMeta(html, ["og:title", "twitter:title", "title", "<title>", "og:site_name"]) ?? domain
        let description = extractMeta(html, ["og:description", "twitter:description", "description"])
        let image = extractMeta(html, ["og:image", "twitter:image"]).flatMap { absoluteURL($0, relativeTo: url) }
        return LinkMetadata(url: url.absoluteString, domain: domain, title: title, description: description, imageURL: image)
    }

    /// Tries each name in order, matching `<meta property=…>`, `<meta name=…>`,
    /// content-first ordering, and the `<title>` tag — mirroring the site util.
    private static func extractMeta(_ html: String, _ names: [String]) -> String? {
        for name in names {
            if name == "<title>" {
                if let value = firstMatch(html, "<title[^>]*>([^<]+)</title>") {
                    return decodeEntities(value)
                }
                continue
            }
            let key = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                "<meta[^>]*property=[\"']\(key)[\"'][^>]*content=[\"']([^\"']+)[\"']",
                "<meta[^>]*name=[\"']\(key)[\"'][^>]*content=[\"']([^\"']+)[\"']",
                "<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']\(key)[\"']"
            ]
            for pattern in patterns {
                if let value = firstMatch(html, pattern) {
                    return decodeEntities(value)
                }
            }
        }
        return nil
    }

    private static func firstMatch(_ html: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[captured])
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " "
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    private static func absoluteURL(_ string: String, relativeTo base: URL) -> URL? {
        if let url = URL(string: string), url.scheme != nil { return url }
        return URL(string: string, relativeTo: base)?.absoluteURL
    }
}

/// In-memory cache so revisiting a note doesn't refetch.
private actor MetadataCache {
    private var store: [String: LinkMetadata] = [:]
    func get(_ key: String) -> LinkMetadata? {
        store[key]
    }

    func set(_ key: String, _ value: LinkMetadata) {
        store[key] = value
    }
}
