import Foundation
import SwiftData

/// A note's relationship to the GitHub repo.
enum SyncState: String {
    case localOnly // exists only in the app, never pushed
    case draft // committed to main with `draft: true`
    case published // committed to main with `draft: false`
}

/// A single note. Doubles as the local-only draft store and the local cache of
/// a note that exists in the repo (tracked by `remotePath` + `remoteSha`).
@Model
final class Note {
    var id: UUID
    var title: String
    var body: String
    var sourceURL: String?
    /// Custom URL slug. When nil, the site derives the slug from the filename.
    var customSlug: String?
    var tags: [String]
    var noteDescription: String?
    var pubDate: Date
    /// The frontmatter `draft` flag last written to the repo.
    var draftFlag: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Set once the note exists in the repo, e.g.
    /// "src/content/notes/2026-06-28-some-slug.md". Stable across edits.
    var remotePath: String?
    /// The current blob SHA of the remote file, required to update it.
    var remoteSha: String?
    /// Hash of this note's serialized content at the last successful push or
    /// pull. Used to detect local edits that haven't been sent to GitHub.
    var syncedContentHash: String?

    init(
        title: String = "",
        body: String = "",
        sourceURL: String? = nil,
        customSlug: String? = nil,
        tags: [String] = [],
        noteDescription: String? = nil,
        pubDate: Date = Date(),
        draftFlag: Bool = true
    ) {
        id = UUID()
        self.title = title
        self.body = body
        self.sourceURL = sourceURL
        self.customSlug = customSlug
        self.tags = tags
        self.noteDescription = noteDescription
        self.pubDate = pubDate
        self.draftFlag = draftFlag
        createdAt = Date()
        updatedAt = Date()
    }

    var syncState: SyncState {
        guard remotePath != nil else { return .localOnly }
        return draftFlag ? .draft : .published
    }

    /// Hash of the note's content as it would be serialized right now.
    var currentContentHash: String {
        FrontmatterSerializer.contentHash(of: FrontmatterSerializer.serialize(self))
    }

    /// True when a GitHub-backed note has local edits not yet pushed.
    /// Local-only notes are never "diverged" — they're entirely unpushed by nature.
    var hasUnpushedChanges: Bool {
        guard remotePath != nil else { return false }
        return currentContentHash != syncedContentHash
    }

    /// Records the current content as the synced baseline. Call after a
    /// successful push or pull so divergence is measured from here.
    func markSynced() {
        syncedContentHash = currentContentHash
    }

    /// Populates the editable fields from parsed frontmatter, used when
    /// importing or reloading a note from the repo. Leaves `pubDate` untouched
    /// when the frontmatter has none.
    func apply(_ parsed: ParsedFrontmatter) {
        title = parsed.title
        body = parsed.body
        sourceURL = parsed.sourceURL
        customSlug = parsed.customSlug
        tags = parsed.tags
        noteDescription = parsed.description
        draftFlag = parsed.draft
        if let pubDate = parsed.pubDate { self.pubDate = pubDate }
    }

    /// Slug used for the filename: custom slug if set, otherwise derived from title.
    var effectiveSlug: String {
        if let customSlug, !customSlug.isEmpty { return customSlug }
        return FrontmatterSerializer.slug(from: title)
    }

    /// The repo path this note should live at. Reuses `remotePath` once set so
    /// the file stays put even if the title later changes.
    var resolvedPath: String {
        if let remotePath { return remotePath }
        let filename = "\(FrontmatterSerializer.dateString(pubDate))-\(effectiveSlug).md"
        return "\(AppConfig.notesDir)/\(filename)"
    }
}
