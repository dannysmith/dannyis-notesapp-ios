import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var token: String = KeychainStore.read() ?? ""
    @State private var status: ValidationStatus = .idle
    @State private var isValidating = false

    enum ValidationStatus: Equatable {
        case idle, ok(String), failed(String)
    }

    private let client = GitHubClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("ghp_… or github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Fine-grained Personal Access Token")
                } footer: {
                    Text(
                        "Scope it to **\(AppConfig.repoSlug)** only, with **Contents: read & write**. " +
                            "Stored in the Keychain on this device."
                    )
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text("Save & Validate")
                    }
                    .disabled(token.isEmpty || isValidating)

                    switch status {
                    case .idle:
                        EmptyView()
                    case let .ok(slug):
                        Label("Connected to \(slug)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case let .failed(message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if KeychainStore.hasToken {
                    Section {
                        Button(role: .destructive) {
                            KeychainStore.delete()
                            token = ""
                            status = .idle
                        } label: {
                            Text("Remove token")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard KeychainStore.save(token) else {
            status = .failed("Couldn't save the token to the Keychain.")
            return
        }
        isValidating = true
        status = .idle
        Task {
            defer { isValidating = false }
            do {
                let repo = try await client.validate()
                status = .ok(repo.fullName)
            } catch {
                status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}
