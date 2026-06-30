import Foundation

/// An entry in a directory listing from the Contents API.
struct GHContentEntry: Codable, Identifiable {
    let name: String
    let path: String
    let sha: String
    let type: String // "file" | "dir"
    var id: String {
        path
    }
}

/// A single file fetched from the Contents API (base64-encoded content).
struct GHFile: Codable {
    let content: String
    let sha: String
    let encoding: String

    /// Decoded UTF-8 text, or nil if the content isn't base64-encoded UTF-8.
    /// Files over ~1 MB come back as `encoding: "none"` with empty content
    /// (fetch them via the Blobs/raw API instead); guarding the encoding keeps
    /// that case from silently decoding to an empty string.
    var decodedText: String? {
        guard encoding == "base64" else { return nil }
        // GitHub wraps the base64 payload at 60 columns; ignore the newlines.
        guard let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Minimal repo metadata, used to validate a token.
struct GHRepo: Codable {
    let fullName: String
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case defaultBranch = "default_branch"
    }
}

/// Response from a create/update/delete file call.
struct GHWriteResponse: Codable {
    let content: GHContentMeta?
    let commit: GHCommitMeta
}

struct GHContentMeta: Codable {
    let path: String?
    let sha: String?
}

struct GHCommitMeta: Codable {
    let sha: String
    let htmlURL: String?
    enum CodingKeys: String, CodingKey {
        case sha
        case htmlURL = "html_url"
    }
}

enum GitHubError: LocalizedError {
    case missingToken
    case invalidResponse
    case http(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "No GitHub token. Add one in Settings."
        case .invalidResponse:
            "Unexpected response from GitHub."
        case let .http(status, message):
            "GitHub error \(status): \(message)"
        case let .decoding(detail):
            "Couldn't read GitHub's response: \(detail)"
        }
    }
}
