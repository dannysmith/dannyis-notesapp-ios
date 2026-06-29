import SwiftUI

/// A small preview card for a note's `sourceURL`, mirroring the site's
/// `BookmarkCard.astro` (image, title, description, domain). Fetches metadata
/// asynchronously and degrades gracefully when it's unavailable.
struct BookmarkCardView: View {
    let urlString: String

    @State private var metadata: LinkMetadata?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        // A concrete container (not Group) so `.task` always has a view to
        // attach to — a Group with no children on first render never runs it.
        VStack(alignment: .leading, spacing: 0) {
            if let metadata {
                card(metadata)
            } else if isLoading {
                Label("Loading preview…", systemImage: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if failed {
                fallback
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: urlString) { await load() }
    }

    private func card(_ metadata: LinkMetadata) -> some View {
        Link(destination: URL(string: metadata.url) ?? fallbackURL) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .lineLimit(2)
                    if let description = metadata.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(metadata.domain)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let imageURL = metadata.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(.secondarySystemFill)
                    }
                    .frame(width: 84, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var fallback: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(domainOrURL).font(.caption)
                Text("Preview unavailable").font(.caption2).foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: "link")
        }
        .foregroundStyle(.secondary)
    }

    private var domainOrURL: String {
        URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }

    private var fallbackURL: URL {
        URL(string: "https://danny.is")!
    }

    private func load() async {
        metadata = nil
        failed = false
        guard URL(string: urlString) != nil, !urlString.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
        // Debounce so typing a URL doesn't fire a request per keystroke.
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }

        let result = await LinkMetadataService.fetch(urlString)
        if Task.isCancelled { return }
        if let result {
            metadata = result
        } else {
            failed = true
        }
    }
}
