import SwiftUI

/// Compact status row at the top of the editor: an icon coloured by where the
/// note lives, its filename, and — for notes already on GitHub — whether it has
/// local edits not yet pushed. The state's name lives in the nav-bar title.
struct NoteStatusHeader: View {
    let note: Note

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(filename)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if note.hasUnpushedChanges {
                Text("Local changes")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // A state-tinted capsule marks this as informational, not an input.
        .background(color.opacity(0.12), in: Capsule())
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
}
