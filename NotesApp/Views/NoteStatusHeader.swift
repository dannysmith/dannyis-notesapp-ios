import SwiftUI

/// Prominent status banner shown at the top of the editor: where this note
/// currently lives (this device / draft on GitHub / published), and whether it
/// has local edits not yet pushed.
struct NoteStatusHeader: View {
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
                if note.hasUnpushedChanges {
                    Text("Local changes not pushed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
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
