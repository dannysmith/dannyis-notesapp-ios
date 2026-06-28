import SwiftUI

/// A push/publish/maintenance action available in the editor.
enum EditorAction: Identifiable {
    case pushDraft, updateDraft, publish, updatePublished, revertToDraft
    case reloadFromGitHub, deleteRemote
    var id: Self {
        self
    }
}

struct ActionConfirm {
    let title: String
    let message: String
    let button: String
    let destructive: Bool
}

/// Presentation + confirmation copy for a button.
struct ActionStyle {
    let label: String
    let icon: String
    var tint: Color?
    var confirm: ActionConfirm?
}

/// Maps an action to its button styling and (where required) its confirmation
/// copy. Confirmation is required for anything that creates or changes a live
/// published note, plus the destructive reload/delete actions.
func actionStyle(for action: EditorAction, syncState: SyncState) -> ActionStyle {
    switch action {
    case .pushDraft:
        ActionStyle(label: "Push draft to GitHub", icon: "arrow.up.doc")
    case .updateDraft:
        ActionStyle(label: "Update draft on GitHub", icon: "arrow.up.doc")
    case .publish:
        ActionStyle(
            label: syncState == .localOnly ? "Publish to GitHub" : "Publish on GitHub",
            icon: "paperplane.fill",
            tint: .green,
            confirm: ActionConfirm(
                title: "Publish to your live site?",
                message: "This creates a published note on danny.is on the next deploy.",
                button: "Publish",
                destructive: false
            )
        )
    case .updatePublished:
        ActionStyle(
            label: "Update published note",
            icon: "paperplane.fill",
            tint: .green,
            confirm: ActionConfirm(
                title: "Update the published note?",
                message: "This changes the live note on danny.is on the next deploy.",
                button: "Update",
                destructive: false
            )
        )
    case .revertToDraft:
        ActionStyle(
            label: "Revert to draft",
            icon: "arrow.uturn.backward",
            tint: .orange,
            confirm: ActionConfirm(
                title: "Revert to draft?",
                message: "This removes the note from your live site on the next deploy.",
                button: "Revert to draft",
                destructive: true
            )
        )
    case .reloadFromGitHub:
        ActionStyle(
            label: "Reload from GitHub",
            icon: "arrow.down.circle",
            confirm: ActionConfirm(
                title: "Reload from GitHub?",
                message: "This replaces your local edits with the current version on GitHub.",
                button: "Discard local edits",
                destructive: true
            )
        )
    case .deleteRemote:
        ActionStyle(
            label: "Delete from GitHub",
            icon: "trash",
            confirm: ActionConfirm(
                title: "Delete from GitHub?",
                message: "This deletes the note's file from the repo on the next deploy.",
                button: "Delete",
                destructive: true
            )
        )
    }
}
