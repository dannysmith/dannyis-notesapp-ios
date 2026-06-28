import SwiftData
import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var tagsText: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// The slug value this view last auto-generated. While the current slug
    /// matches it, we keep syncing from the title; once the user edits or
    /// clears the slug, it diverges and we stop.
    @State private var lastAutoSlug = ""

    private let client = GitHubClient()

    var body: some View {
        Form {
            Section {
                NoteStatusHeader(note: note)
            }

            Section("Title") {
                TextField("Title", text: $note.title, axis: .vertical)
            }

            Section("Body") {
                TextField("Write your note…", text: $note.body, axis: .vertical)
                    .lineLimit(6...)
                    .font(.system(.body, design: .serif))
            }

            Section("Metadata") {
                TextField("Source URL", text: Binding(
                    get: { note.sourceURL ?? "" },
                    set: { note.sourceURL = $0.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                HStack {
                    TextField("Custom slug (optional)", text: Binding(
                        get: { note.customSlug ?? "" },
                        set: { note.customSlug = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if !(note.customSlug ?? "").isEmpty {
                        Button {
                            note.customSlug = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear slug")
                    }
                }

                TextField("Tags (comma separated)", text: $tagsText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: tagsText) { _, newValue in
                        note.tags = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }

                DatePicker("Publish date", selection: $note.pubDate, displayedComponents: .date)
            }

            Section {
                Button {
                    saveLocal()
                } label: {
                    Label("Save locally", systemImage: "tray.and.arrow.down")
                }

                Button {
                    push(asDraft: true)
                } label: {
                    Label("Push as draft", systemImage: "arrow.up.doc")
                }

                Button {
                    push(asDraft: false)
                } label: {
                    Label(note.syncState == .published ? "Update published note" : "Publish", systemImage: "paperplane")
                }
                .tint(.green)
            }
            .disabled(isWorking || note.title.isEmpty)

            if note.remotePath != nil {
                Section {
                    Button(role: .destructive) {
                        remoteDelete()
                    } label: {
                        Label("Delete from GitHub", systemImage: "trash")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking {
                ProgressView().controlSize(.large)
            }
        }
        .onChange(of: note.title) { _, newTitle in
            syncSlug(from: newTitle)
        }
        .onAppear {
            tagsText = note.tags.joined(separator: ", ")
            lastAutoSlug = note.customSlug ?? ""
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Auto-fills the slug from the title for notes not yet pushed, until the
    /// user takes over the slug field. Never touches the slug of a note that
    /// already exists in the repo (changing it would change its public URL).
    private func syncSlug(from title: String) {
        guard note.remotePath == nil else { return }
        guard (note.customSlug ?? "") == lastAutoSlug else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = trimmed.isEmpty ? "" : FrontmatterSerializer.slug(from: trimmed)
        note.customSlug = generated.isEmpty ? nil : generated
        lastAutoSlug = generated
    }

    private func saveLocal() {
        note.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }

    private func push(asDraft: Bool) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                note.draftFlag = asDraft
                let path = note.resolvedPath
                let content = FrontmatterSerializer.serialize(note)
                let verb = asDraft ? "Draft" : "Publish"
                let message = "\(verb) note: \(note.title)"
                let response = try await client.putFile(
                    path: path,
                    content: content,
                    message: message,
                    sha: note.remoteSha
                )
                note.remotePath = response.content?.path ?? path
                note.remoteSha = response.content?.sha
                note.updatedAt = Date()
                try? modelContext.save()
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func remoteDelete() {
        guard let path = note.remotePath, let sha = note.remoteSha else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await client.deleteFile(path: path, sha: sha, message: "Delete note: \(note.title)")
                modelContext.delete(note)
                try? modelContext.save()
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Prominent status banner shown at the top of the editor: where this note
/// currently lives (this device / draft on GitHub / published).
private struct NoteStatusHeader: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var filename: String {
        let path = note.remotePath ?? note.resolvedPath
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    private var icon: String {
        switch note.syncState {
        case .localOnly: "iphone"
        case .draft: "doc.badge.ellipsis"
        case .published: "checkmark.seal.fill"
        }
    }

    private var color: Color {
        switch note.syncState {
        case .localOnly: .secondary
        case .draft: .orange
        case .published: .green
        }
    }

    private var title: String {
        switch note.syncState {
        case .localOnly: "Local draft"
        case .draft: "Draft on GitHub"
        case .published: "Published"
        }
    }

    private var detail: String {
        switch note.syncState {
        case .localOnly: "Only on this device · \(filename)"
        case .draft: "On \(AppConfig.branch) · \(filename)"
        case .published: "On \(AppConfig.branch) · \(filename)"
        }
    }
}
