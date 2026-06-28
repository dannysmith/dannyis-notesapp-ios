import Foundation

/// Thin async wrapper over the GitHub REST Contents API.
///
/// For this app's needs (one file per commit) the Contents API is the whole
/// story: `PUT .../contents/{path}` creates or updates a file *as a commit* in
/// a single request. No git client, clone, or working copy required.
struct GitHubClient {
    private let session: URLSession
    private let apiBase = URL(string: "https://api.github.com")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Validates the stored token by fetching repo metadata.
    func validate() async throws -> GHRepo {
        try await get("/repos/\(AppConfig.repoSlug)", as: GHRepo.self)
    }

    /// Lists `.md`/`.mdx` files in the notes directory.
    func listNotes() async throws -> [GHContentEntry] {
        let path = "/repos/\(AppConfig.repoSlug)/contents/\(AppConfig.notesDir)?ref=\(AppConfig.branch)"
        let entries = try await get(path, as: [GHContentEntry].self)
        return entries.filter { $0.type == "file" && ($0.name.hasSuffix(".md") || $0.name.hasSuffix(".mdx")) }
    }

    /// Fetches a single file's decoded text and current SHA.
    func fetchFile(path: String) async throws -> (text: String, sha: String) {
        let endpoint = "/repos/\(AppConfig.repoSlug)/contents/\(path)?ref=\(AppConfig.branch)"
        let file = try await get(endpoint, as: GHFile.self)
        guard let text = file.decodedText else {
            throw GitHubError.decoding("file content was not valid UTF-8")
        }
        return (text, file.sha)
    }

    /// Creates (sha == nil) or updates (sha != nil) a file as a single commit.
    @discardableResult
    func putFile(path: String, content: String, message: String, sha: String?) async throws -> GHWriteResponse {
        struct Body: Encodable {
            let message: String
            let content: String
            let branch: String
            let sha: String?
        }
        let body = Body(
            message: message,
            content: Data(content.utf8).base64EncodedString(),
            branch: AppConfig.branch,
            sha: sha
        )
        return try await send("PUT", "/repos/\(AppConfig.repoSlug)/contents/\(path)", body: body, as: GHWriteResponse.self)
    }

    /// Deletes a file as a single commit.
    @discardableResult
    func deleteFile(path: String, sha: String, message: String) async throws -> GHWriteResponse {
        struct Body: Encodable {
            let message: String
            let sha: String
            let branch: String
        }
        let body = Body(message: message, sha: sha, branch: AppConfig.branch)
        return try await send("DELETE", "/repos/\(AppConfig.repoSlug)/contents/\(path)", body: body, as: GHWriteResponse.self)
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let request = try makeRequest("GET", path)
        return try await perform(request, as: type)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: some Encodable, as type: T.Type) async throws -> T {
        var request = try makeRequest(method, path)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request, as: type)
    }

    private func makeRequest(_ method: String, _ path: String) throws -> URLRequest {
        guard let token = KeychainStore.read(), !token.isEmpty else {
            throw GitHubError.missingToken
        }
        guard let url = URL(string: apiBase.absoluteString + path) else {
            throw GitHubError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest, as _: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw GitHubError.http(status: http.statusCode, message: Self.message(from: data))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GitHubError.decoding(error.localizedDescription)
        }
    }

    /// Pulls the `message` field out of a GitHub error JSON body, if present.
    private static func message(from data: Data) -> String {
        struct ErrorBody: Decodable { let message: String }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return body.message
        }
        return String(data: data, encoding: .utf8) ?? "unknown error"
    }
}
