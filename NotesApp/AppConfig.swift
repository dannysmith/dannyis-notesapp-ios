import Foundation

/// Static configuration for the single repo this app targets.
/// The app is personal/single-user, so these are hard-coded rather than
/// configurable. Auth is a fine-grained PAT stored in the Keychain.
enum AppConfig {
    static let owner = "dannysmith"
    static let repo = "dannyis-astro"
    static let branch = "main"
    static let notesDir = "src/content/notes"

    static var repoSlug: String {
        "\(owner)/\(repo)"
    }
}
