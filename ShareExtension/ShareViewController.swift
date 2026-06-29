import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Principal view controller for the Share Extension. Extracts the shared URL
/// and/or text, then hosts the SwiftUI compose sheet.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await loadAndPresent() }
    }

    private func loadAndPresent() async {
        let (sourceURL, text) = await extractSharedContent()
        let body = text.map(ShareFormatting.blockquote) ?? ""
        let initial = SharePayload(sourceURL: sourceURL, body: body, createdAt: Date())

        let composeView = ShareComposeView(
            initial: initial,
            onSave: { [weak self] payload in
                ShareInbox.write(payload)
                self?.complete()
            },
            onCancel: { [weak self] in self?.cancel() }
        )

        let host = UIHostingController(rootView: composeView)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    // MARK: - Extraction

    private func extractSharedContent() async -> (url: String?, text: String?) {
        var url: String?
        var text: String?
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    url = await loadURL(provider)
                } else if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    text = await loadText(provider)
                }
            }
        }
        return (url, text)
    }

    /// Each loader extracts a Sendable `String` inside the completion, so no
    /// non-Sendable item crosses the continuation boundary (Swift 6 safe).
    private func loadURL(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: (item as? URL)?.absoluteString)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    // MARK: - Completion

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "is.danny.notesapp.ShareExtension", code: 0))
    }
}
