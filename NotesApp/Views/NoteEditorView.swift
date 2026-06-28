import SwiftData
import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var tagsText: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var pendingAction: EditorAction?
    @State private var showConflict = false
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
                ForEach(primaryActions) { action in
                    actionButton(action)
                }
            }
            .disabled(isWorking || note.title.isEmpty)

            if note.hasUnpushedChanges {
                Section {
                    Button {
                        trigger(.reloadFromGitHub)
                    } label: {
                        Label("Reload from GitHub", systemImage: "arrow.down.circle")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("Replaces your local edits with the current version on GitHub.")
                }
            }

            if note.remotePath != nil {
                Section {
                    Button(role: .destructive) {
                        trigger(.deleteRemote)
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
        .onDisappear {
            // Edits auto-persist, but force a save when leaving for safety.
            try? modelContext.save()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationPresented,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            if let confirm = style(for: action).confirm {
                Button(confirm.button, role: confirm.destructive ? .destructive : nil) {
                    execute(action)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(style(for: action).confirm?.message ?? "")
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Note changed on GitHub", isPresented: $showConflict) {
            Button("Keep my version") { forcePush() }
            Button("Use GitHub version", role: .destructive) { reload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note was edited on GitHub since you last synced. " +
                "“Keep my version” overwrites GitHub with your local copy; " +
                "“Use GitHub version” discards your local edits.")
        }
    }

    // MARK: - Actions

    /// The two primary buttons shown for the note's current state.
    private var primaryActions: [EditorAction] {
        switch note.syncState {
        case .localOnly: [.pushDraft, .publish]
        case .draft: [.updateDraft, .publish]
        case .published: [.updatePublished, .revertToDraft]
        }
    }

    @ViewBuilder
    private func actionButton(_ action: EditorAction) -> some View {
        let style = style(for: action)
        Button {
            trigger(action)
        } label: {
            Label(style.label, systemImage: style.icon)
        }
        .tint(style.tint)
    }

    /// Either prompt for confirmation or run the action immediately.
    private func trigger(_ action: EditorAction) {
        if style(for: action).confirm != nil {
            pendingAction = action
        } else {
            execute(action)
        }
    }

    private func execute(_ action: EditorAction) {
        switch action {
        case .pushDraft, .updateDraft, .revertToDraft:
            push(asDraft: true)
        case .publish, .updatePublished:
            push(asDraft: false)
        case .reloadFromGitHub:
            reload()
        case .deleteRemote:
            remoteDelete()
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )
    }

    private var confirmationTitle: String {
        pendingAction.flatMap { style(for: $0).confirm?.title } ?? ""
    }

    /// Styling + confirmation copy for an action (see `NoteEditorActions`).
    private func style(for action: EditorAction) -> ActionStyle {
        actionStyle(for: action, syncState: note.syncState)
    }

    // MARK: - Slug

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

    // MARK: - Networking

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
                note.markSynced()
                note.updatedAt = Date()
                try? modelContext.save()
                dismiss()
            } catch let GitHubError.http(status, _) where status == 409 {
                // Remote moved since we last synced — let the user choose.
                showConflict = true
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Resolves a conflict by overwriting GitHub with the local version: fetch
    /// the latest SHA, then re-push the current local content over it.
    private func forcePush() {
        guard let path = note.remotePath else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let (_, latestSha) = try await client.fetchFile(path: path)
                let content = FrontmatterSerializer.serialize(note)
                let response = try await client.putFile(
                    path: path,
                    content: content,
                    message: "Update note: \(note.title)",
                    sha: latestSha
                )
                note.remoteSha = response.content?.sha
                note.markSynced()
                note.updatedAt = Date()
                try? modelContext.save()
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Replaces local content with the current version on GitHub.
    private func reload() {
        guard let path = note.remotePath else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let (text, sha) = try await client.fetchFile(path: path)
                let parsed = FrontmatterSerializer.parse(text)
                note.title = parsed.title
                note.body = parsed.body
                note.sourceURL = parsed.sourceURL
                note.customSlug = parsed.customSlug
                note.tags = parsed.tags
                note.noteDescription = parsed.description
                if let pubDate = parsed.pubDate { note.pubDate = pubDate }
                note.draftFlag = parsed.draft
                note.remoteSha = sha
                note.markSynced()
                note.updatedAt = Date()
                tagsText = note.tags.joined(separator: ", ")
                lastAutoSlug = note.customSlug ?? ""
                try? modelContext.save()
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
