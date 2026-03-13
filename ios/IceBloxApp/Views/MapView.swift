import MapKit
import SwiftUI

struct MapView: View {
    @Environment(\.dismiss) private var dismiss

    #if APPSTORE_SCREENSHOTS
    private static let screenshotSightings: [MapSighting] = [
        MapSighting(
            latitude: 34.0522, longitude: -118.2437, confidence: 0.85,
            seenAt: "2026-03-12T10:30:00Z", type: "detection", description: nil, photoUrl: nil),
        MapSighting(
            latitude: 34.0195, longitude: -118.2910, confidence: 0.35,
            seenAt: "2026-03-12T09:15:00Z", type: "report", description: nil, photoUrl: nil),
        MapSighting(
            latitude: 34.0725, longitude: -118.2615, confidence: 0.40,
            seenAt: "2026-03-11T14:45:00Z", type: "report", description: nil, photoUrl: nil)
    ]
    @State private var sightings: [MapSighting] = screenshotSightings
    @State private var isLoading = false
    @State private var isOffline = false
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.27),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    ))
    #else
    @StateObject private var locationManager = LocationManager()
    @State private var sightings: [MapSighting] = MapView.loadCachedSightings()
    @State private var isLoading = true
    @State private var isOffline = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var fetchTask: Task<Void, Never>?
    private let mapClient = MapClient()
    #endif

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
                        #if APPSTORE_SCREENSHOTS
                        Map(position: $cameraPosition) {
                            ForEach(Array(sightings.enumerated()), id: \.offset) { _, sighting in
                                Marker(
                                    sighting.confidence >= 0.5 ? "ICE Activity Detected" : "Potential ICE Activity",
                                    coordinate: CLLocationCoordinate2D(
                                        latitude: sighting.latitude,
                                        longitude: sighting.longitude
                                    )
                                )
                                .tint(sighting.confidence >= 0.5 ? .red : .yellow)
                            }
                        }
                        #else
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
                        #endif

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
            #if APPSTORE_SCREENSHOTS
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "app.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("IceBlox")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("now")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("ICE Activity Detected")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("A vehicle matching known ICE plates was spotted near your location.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            }
            #endif
            #if !APPSTORE_SCREENSHOTS
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
            #endif
        }
    }

    #if !APPSTORE_SCREENSHOTS
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
    #endif
}
