import SwiftUI

struct ContactView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var message = ""
    @State private var includeLogs = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    private let client = ContactClient()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            Text("Name (optional)")
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.caption)
                            TextField("Your name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        Group {
                            Text("Email (optional)")
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.caption)
                            TextField("you@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                        }

                        Group {
                            Text("Message *")
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.caption)
                            TextEditor(text: $message)
                                .frame(minHeight: 150)
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Toggle("Include diagnostic logs", isOn: $includeLogs)
                            .tint(.blue)
                            .foregroundStyle(.white)

                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }

                        if didSubmit {
                            Text("Message sent. Thank you!")
                                .foregroundStyle(.green)
                                .font(.callout)
                        }

                        Button {
                            submit()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            } else {
                                Text("Send")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(message.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    }
                    .padding()
                }
            }
            .navigationTitle("Contact Us")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil

        var logs: String?
        if includeLogs {
            let entries = DebugLog.shared.entries
            let formatter = ISO8601DateFormatter()
            logs = entries.map { entry in
                let level: String
                switch entry.level {
                case .debug: level = "D"
                case .warning: level = "W"
                case .error: level = "E"
                }
                return "[\(formatter.string(from: entry.timestamp))] [\(level)] [\(entry.tag)] \(entry.message)"
            }.joined(separator: "\n")
        }

        client.submitContact(name: name, email: email, message: message, logs: logs) { result in
            DispatchQueue.main.async {
                isSubmitting = false
                switch result {
                case .success:
                    didSubmit = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
