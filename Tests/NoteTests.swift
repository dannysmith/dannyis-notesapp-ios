import Foundation
import Testing
@testable import NotesApp

struct NoteTests {
    @Test func newNoteIsLocalOnly() {
        let note = Note(title: "x")
        #expect(note.syncState == .localOnly)
        #expect(note.hasUnpushedChanges == false)
    }

    @Test func syncStateReflectsDraftFlag() {
        let note = Note(title: "x")
        note.remotePath = "src/content/notes/2026-01-01-x.md"
        note.draftFlag = true
        #expect(note.syncState == .draft)
        note.draftFlag = false
        #expect(note.syncState == .published)
    }

    @Test func unpushedChangesTrackAgainstSyncedBaseline() {
        let note = Note(title: "x", body: "one")
        note.remotePath = "p"
        note.markSynced()
        #expect(note.hasUnpushedChanges == false)

        note.body = "two"
        #expect(note.hasUnpushedChanges == true)

        note.markSynced()
        #expect(note.hasUnpushedChanges == false)
    }

    @Test func effectiveSlugPrefersCustomSlug() {
        let note = Note(title: "Hello World")
        #expect(note.effectiveSlug == "hello-world")
        note.customSlug = "custom-one"
        #expect(note.effectiveSlug == "custom-one")
    }

    @Test func resolvedPathUsesRemotePathOnceSet() {
        let note = Note(title: "Hello World", pubDate: Date(timeIntervalSince1970: 0))
        #expect(note.resolvedPath == "src/content/notes/1970-01-01-hello-world.md")
        note.remotePath = "src/content/notes/custom.md"
        #expect(note.resolvedPath == "src/content/notes/custom.md")
    }
}
