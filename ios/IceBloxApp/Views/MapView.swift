import MapKit
import SwiftUI

struct MapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager()

    @State private var sightings: [MapSighting] = MapView.loadCachedSightings()
    @State private var isLoading = true
    @State private var isOffline = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var fetchTask: Task<Void, Never>?

    private let mapClient = MapClient()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("Reported ICE vehicles near you")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.black)

                    if isOffline {
                        Text("Offline — showing cached data")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(Color.black)
                    }

                    ZStack {
                        Map(position: $cameraPosition) {
                            UserAnnotation()
                            ForEach(Array(sightings.enumerated()), id: \.offset) { _, sighting in
                                Annotation(
                                    sighting.confidence >= 0.5 ? "Likely ICE activity" : "Potential ICE activity",
                                    coordinate: CLLocationCoordinate2D(
                                        latitude: sighting.latitude,
                                        longitude: sighting.longitude
                                    )
                                ) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(sighting.confidence >= 0.5 ? .red : .yellow)
                                }
                            }
                        }
                        .onMapCameraChange(frequency: .onEnd) { context in
                            let center = context.region.center
                            let span = context.region.span
                            let radiusMiles = span.latitudeDelta * 69.0 / 2
                            scheduleFetch(lat: center.latitude, lng: center.longitude, radius: radiusMiles)
                        }

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                        }
                    }
                }
            }
            .navigationTitle("View Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .onAppear {
                locationManager.requestPermission()
                if let lat = locationManager.latitude, let lng = locationManager.longitude {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    ))
                }
            }
            .onChange(of: locationManager.latitude) { _, newLat in
                if let lat = newLat, let lng = locationManager.longitude,
                   cameraPosition == .automatic {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                    ))
                }
            }
        }
    }

    private func scheduleFetch(lat: Double, lng: Double, radius: Double) {
        fetchTask?.cancel()
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let clampedRadius = min(max(radius, 1), 500)
            isLoading = true
            do {
                let result = try await mapClient.fetchSightings(lat: lat, lng: lng, radius: clampedRadius)
                sightings = result
                isOffline = false
                MapView.saveCachedSightings(result)
            } catch {
                if !Task.isCancelled {
                    isOffline = true
                }
            }
            isLoading = false
        }
    }

    private static let cacheKey = "cached_map_sightings"

    static func saveCachedSightings(_ sightings: [MapSighting]) {
        guard let data = try? JSONEncoder().encode(sightings) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    static func loadCachedSightings() -> [MapSighting] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let sightings = try? JSONDecoder().decode([MapSighting].self, from: data) else {
            return []
        }
        return sightings
    }
}
