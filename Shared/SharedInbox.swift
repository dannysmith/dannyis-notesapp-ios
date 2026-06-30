import Foundation

/// A single item captured by the Share Extension, handed to the main app via a
/// JSON file in the shared App Group container. This is the only contract
/// between the two targets — they don't share a module.
struct SharePayload: Codable {
    var sourceURL: String?
    var body: String
    var createdAt: Date
}

/// File-based handoff between the Share Extension (writes) and the app (reads).
///
/// Using a plain directory of JSON files in the App Group container — rather
/// than a shared SwiftData store — keeps the extension tiny and sidesteps
/// cross-process Core Data/SwiftData pitfalls.
enum ShareInbox {
    static let appGroupID = "group.is.danny.notesapp"

    private static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("ShareInbox", isDirectory: true)
    }

    /// Queues a shared item (called from the extension). Returns false if the
    /// payload couldn't be written, so the caller can report failure rather
    /// than dismiss the share sheet as if it had saved.
    @discardableResult
    static func write(_ payload: SharePayload) -> Bool {
        guard let directory else { return false }
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Reads and removes all queued items, oldest first (called from the app).
    static func drain() -> [SharePayload] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        let decoder = JSONDecoder()
        var payloads: [SharePayload] = []
        for file in files where file.pathExtension == "json" {
            // Only delete a file once we've successfully read it, so a transient
            // read/decode failure leaves the payload to retry next time rather
            // than dropping it.
            guard let data = try? Data(contentsOf: file),
                  let payload = try? decoder.decode(SharePayload.self, from: data) else { continue }
            payloads.append(payload)
            try? FileManager.default.removeItem(at: file)
        }
        return payloads.sorted { $0.createdAt < $1.createdAt }
    }
}
