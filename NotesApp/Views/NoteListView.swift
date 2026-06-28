import SwiftData
import SwiftUI

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var showingSettings = false
    @State private var newNote: Note?
    @State private var isPulling = false
    @State private var errorMessage: String?

    private let client = GitHubClient()

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "note.text",
                        description: Text("Tap + to write one, or pull existing notes from GitHub.")
                    )
                } else {
                    List {
                        ForEach(notes) { note in
                            NavigationLink {
                                NoteEditorView(note: note)
                            } label: {
                                NoteRow(note: note)
                            }
                        }
                        .onDelete(perform: deleteLocal)
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let note = Note()
                        modelContext.insert(note)
                        newNote = note
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        pull()
                    } label: {
                        if isPulling {
                            ProgressView()
                        } else {
                            Label("Pull from GitHub", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isPulling)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(item: $newNote) { note in
                NoteEditorView(note: note)
            }
            .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteLocal(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(notes[index])
        }
    }

    /// Fetches every remote note, imports any not already tracked locally, and
    /// excludes notes with `styleguide: true` entirely — skipping new ones and
    /// removing any that were imported before this exclusion existed.
    private func pull() {
        isPulling = true
        let client = client
        Task {
            defer { isPulling = false }
            do {
                let entries = try await client.listNotes()
                let fetched = try await Self.fetchAll(entries, using: client)

                var localByPath: [String: Note] = [:]
                for note in notes {
                    if let path = note.remotePath { localByPath[path] = note }
                }

                for (entry, text, _) in fetched {
                    let parsed = FrontmatterSerializer.parse(text)
                    if parsed.styleguide {
                        if let existing = localByPath[entry.path] {
                            modelContext.delete(existing)
                        }
                        continue
                    }
                    // Keep any local copy (and its unpushed edits) as-is.
                    if localByPath[entry.path] != nil { continue }

                    let note = Note(
                        title: parsed.title,
                        body: parsed.body,
                        sourceURL: parsed.sourceURL,
                        customSlug: parsed.customSlug,
                        tags: parsed.tags,
                        noteDescription: parsed.description,
                        pubDate: parsed.pubDate ?? Date(),
                        draftFlag: parsed.draft
                    )
                    note.remotePath = entry.path
                    note.remoteSha = entry.sha
                    modelContext.insert(note)
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Fetches all entries' contents concurrently, capped to a few in flight.
    private static func fetchAll(
        _ entries: [GHContentEntry],
        using client: GitHubClient
    ) async throws -> [(entry: GHContentEntry, text: String, sha: String)] {
        let maxConcurrent = 6
        var results: [(entry: GHContentEntry, text: String, sha: String)] = []
        var next = 0

        try await withThrowingTaskGroup(of: (GHContentEntry, String, String).self) { group in
            func schedule() {
                guard next < entries.count else { return }
                let entry = entries[next]
                next += 1
                group.addTask {
                    let (text, sha) = try await client.fetchFile(path: entry.path)
                    return (entry, text, sha)
                }
            }
            for _ in 0 ..< min(maxConcurrent, entries.count) {
                schedule()
            }
            while let result = try await group.next() {
                results.append(result)
                schedule()
            }
        }
        return results
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 8) {
                SyncBadge(state: note.syncState)
                if let url = note.sourceURL, !url.isEmpty {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(note.pubDate, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SyncBadge: View {
    let state: SyncState

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch state {
        case .localOnly: "Local"
        case .draft: "Draft"
        case .published: "Published"
        }
    }

    private var color: Color {
        switch state {
        case .localOnly: .secondary
        case .draft: .orange
        case .published: .green
        }
    }
}
