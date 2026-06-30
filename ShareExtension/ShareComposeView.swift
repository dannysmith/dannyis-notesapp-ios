import SwiftUI

/// The compose sheet shown by the Share Extension: the captured source URL plus
/// an editable body (pre-filled with a blockquote of any shared text). The sheet
/// appears immediately and runs `extract` to fill itself in, so a slow
/// `loadItem` shows a spinner rather than a blank sheet. Saving writes the
/// payload to the shared inbox; the app turns it into a draft.
struct ShareComposeView: View {
    /// Pulls the shared URL and pre-formatted body out of the extension context.
    let extract: @MainActor () async -> (sourceURL: String?, body: String)
    let onSave: (SharePayload) -> Void
    let onCancel: () -> Void

    @State private var sourceURL: String?
    @State private var noteBody = ""
    @State private var isReady = false

    var body: some View {
        NavigationStack {
            Form {
                if isReady {
                    if let sourceURL, !sourceURL.isEmpty {
                        Section("Source URL") {
                            Text(sourceURL)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Section("Note") {
                        TextEditor(text: $noteBody)
                            .frame(minHeight: 160)
                    }
                } else {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Draft") {
                        onSave(SharePayload(sourceURL: sourceURL, body: noteBody, createdAt: Date()))
                    }
                    .disabled(!isReady)
                }
            }
            .task {
                guard !isReady else { return }
                (sourceURL, noteBody) = await extract()
                isReady = true
            }
        }
    }
}
