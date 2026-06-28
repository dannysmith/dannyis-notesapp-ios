import SwiftData
import SwiftUI

@main
struct NotesAppApp: App {
    var body: some Scene {
        WindowGroup {
            NoteListView()
        }
        .modelContainer(for: Note.self)
    }
}
