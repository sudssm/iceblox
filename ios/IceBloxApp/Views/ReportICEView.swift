import MapKit
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
    @State private var pinLatitude: Double?
    @State private var pinLongitude: Double?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private let reportClient = ReportClient()

    private var pinCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: pinLatitude ?? locationManager.latitude ?? 0,
            longitude: pinLongitude ?? locationManager.longitude ?? 0
        )
    }

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

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report Location")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            MapReader { proxy in
                                Map(position: $cameraPosition) {
                                    Marker("Report Location", coordinate: pinCoordinate)
                                        .tint(.red)
                                }
                                .onTapGesture { screenPoint in
                                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                                        pinLatitude = coordinate.latitude
                                        pinLongitude = coordinate.longitude
                                    }
                                }
                            }
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("Tap map to adjust")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .onChange(of: locationManager.latitude) { _, newLat in
                            if pinLatitude == nil, let lat = newLat, let lng = locationManager.longitude {
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                ))
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
            .navigationTitle("Report ICE Activity")
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

        let lat = pinLatitude ?? locationManager.latitude ?? 0
        let lng = pinLongitude ?? locationManager.longitude ?? 0

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
