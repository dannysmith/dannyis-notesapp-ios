import SwiftData
import SwiftUI

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// Newest publish date first; ties broken by most-recently-edited.
    @Query(sort: [
        SortDescriptor(\Note.pubDate, order: .reverse),
        SortDescriptor(\Note.updatedAt, order: .reverse)
    ]) private var notes: [Note]

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
                            // Only local-only drafts can be swiped away. Once a
                            // note exists on GitHub, deleting it here would
                            // silently drop the local copy while leaving the
                            // remote file behind, so we don't offer it.
                            .swipeActions(edge: .trailing) {
                                if note.syncState == .localOnly {
                                    Button(role: .destructive) {
                                        modelContext.delete(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Native large title: it provides the standard scroll-edge blur as
            // content (and the status bar) passes under it, on every iOS version.
            .navigationTitle("danny.is/notes")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        let note = Note()
                        modelContext.insert(note)
                        newNote = note
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    // The primary action: a filled accent-colour button, the
                    // OS-standard prominent style for primary actions.
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)

                    Spacer()

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

                    Spacer()

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Import anything captured by the Share Extension while away.
                importSharedDrafts()
            } else {
                // Flush any pending local edits before the app is suspended/killed.
                try? modelContext.save()
            }
        }
        .onAppear { importSharedDrafts() }
    }

    /// Turns any items the Share Extension queued into local-draft notes, then
    /// fills in each title from the source URL's metadata where possible.
    private func importSharedDrafts() {
        let payloads = ShareInbox.drain()
        guard !payloads.isEmpty else { return }
        var created: [Note] = []
        for payload in payloads {
            let note = Note(body: payload.body, sourceURL: payload.sourceURL)
            modelContext.insert(note)
            created.append(note)
        }
        try? modelContext.save()

        for note in created where note.title.isEmpty && (note.sourceURL?.isEmpty == false) {
            Task { await fillTitleFromMetadata(note) }
        }
    }

    private func fillTitleFromMetadata(_ note: Note) async {
        guard let url = note.sourceURL, let metadata = await LinkMetadataService.fetch(url) else { return }
        // Only use a real page title, not the bare-domain fallback, and don't
        // clobber anything the user has since typed.
        guard note.title.isEmpty, metadata.title != metadata.domain else { return }
        note.title = metadata.title
        note.updatedAt = Date()
        try? modelContext.save()
    }

    /// Fetches every remote note and imports any not already tracked locally.
    /// Notes with `styleguide: true` are excluded entirely: never imported, and
    /// any local copy is deleted.
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

                    let note = Note()
                    note.apply(parsed)
                    note.remotePath = entry.path
                    note.remoteSha = entry.sha
                    note.markSynced()
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
                if note.hasUnpushedChanges {
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
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
