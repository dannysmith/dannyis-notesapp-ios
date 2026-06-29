import SwiftUI

/// The compose sheet shown by the Share Extension: the captured source URL plus
/// an editable body (pre-filled with a blockquote of any shared text). Saving
/// writes the payload to the shared inbox; the app turns it into a draft.
struct ShareComposeView: View {
    @State private var payload: SharePayload
    let onSave: (SharePayload) -> Void
    let onCancel: () -> Void

    init(initial: SharePayload, onSave: @escaping (SharePayload) -> Void, onCancel: @escaping () -> Void) {
        _payload = State(initialValue: initial)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sourceURL = payload.sourceURL, !sourceURL.isEmpty {
                    Section("Source URL") {
                        Text(sourceURL)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Section("Note") {
                    TextEditor(text: $payload.body)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("New Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Draft") { onSave(payload) }
                }
            }
        }
    }
}
