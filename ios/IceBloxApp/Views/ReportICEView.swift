import SwiftUI

struct ReportICEView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager()

    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var description = ""
    @State private var plateNumber = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    private let reportClient = ReportClient()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Button {
                            showCamera = true
                        } label: {
                            if let image = capturedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 250)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 40))
                                    Text("Take Photo")
                                        .font(.headline)
                                }
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description *")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            TextField("What did you see?", text: $description)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Plate Number (optional)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            TextField("e.g. ABC1234", text: $plateNumber)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.allCharacters)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            submitReport()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            } else {
                                Text("Submit Report")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .background(canSubmit ? Color.red : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(!canSubmit || isSubmitting)
                    }
                    .padding()
                }
            }
            .navigationTitle("Report ICE Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPickerView(image: $capturedImage)
            }
            .alert("Report Submitted", isPresented: $didSubmit) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your report has been submitted. Thank you.")
            }
            .onAppear {
                locationManager.requestPermission()
            }
        }
    }

    private var canSubmit: Bool {
        capturedImage != nil && !description.isEmpty
    }

    private func submitReport() {
        guard let image = capturedImage else { return }

        isSubmitting = true
        errorMessage = nil

        let lat = locationManager.latitude ?? 0
        let lng = locationManager.longitude ?? 0

        let submission = ReportSubmission(
            photo: image,
            description: description,
            plateNumber: plateNumber.isEmpty ? nil : plateNumber,
            latitude: lat,
            longitude: lng
        )
        reportClient.submitReport(submission) { result in
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
