//
//  MapSelectionView.swift
//  StikJIT
//
//  Created by Stephen on 11/3/25.
//

import SwiftUI
import MapKit
import UIKit

struct MapSelectionView: UIViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapSelectionView

        init(_ parent: MapSelectionView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let map = gesture.view as? MKMapView
            else { return }

            let point = gesture.location(in: map)
            parent.coordinate = map.convert(point, toCoordinateFrom: map)
        }
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)

        if let coord = coordinate {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coord
            uiView.addAnnotation(annotation)

            let region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            uiView.setRegion(region, animated: true)
        }
    }
}

struct LocationSimulationView: View {
    @Environment(\.themeExpansionManager) private var themeExpansion
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var statusMessage: String = ""
    @State private var statusIsError = false
    @State private var showKeepOpenAlert = false
    @State private var searchQuery = ""
    @State private var searchResults: [SearchResult] = []
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var resendTimer: Timer?
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    private var backgroundStyle: BackgroundStyle {
        themeExpansion?.backgroundStyle(for: appThemeRaw) ?? AppTheme.system.backgroundStyle
    }
    
    private var isAppStoreBuild: Bool {
        #if APPSTORE
        return true
        #else
        return false
        #endif
    }

    private var pairingFilePath: String {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pairingFile.plist")
            .path
    }

    private var pairingExists: Bool {
        FileManager.default.fileExists(atPath: pairingFilePath)
    }

    private var deviceIP: String {
        UserDefaults.standard.string(forKey: "TunnelDeviceIP") ?? "10.7.0.2"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(style: backgroundStyle)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        searchCard
                        mapCard
                        actionsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }

                if showKeepOpenAlert {
                    CustomErrorView(
                        title: "Keep StikDebug Open",
                        message: "Location simulation stops if the app is backgrounded. Keep StikDebug in the foreground while testing.",
                        onDismiss: { showKeepOpenAlert = false },
                        primaryButtonText: "OK",
                        showSecondaryButton: false,
                        messageType: .info
                    )
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                }
            }
            .navigationTitle("Location Simulator")
            .onDisappear {
                stopResendLoop()
                endBackgroundTask()
            }
        }
    }

    private var searchCard: some View {
        MaterialCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick a Location")
                    .font(.headline)
                    .foregroundColor(.primary)
                searchField
                if !searchResults.isEmpty {
                    Divider()
                    ForEach(searchResults) { result in
                        Button(action: { select(result: result) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if result.id != searchResults.last?.id {
                            Divider()
                        }
                    }
                }
                if !pairingExists && !isAppStoreBuild {
                    Label("Import a pairing file first.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if isAppStoreBuild {
                    Label("Location simulation is unavailable in App Store builds.", systemImage: "nosign")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search for a place", text: $searchQuery, onCommit: performSearch)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mapCard: some View {
        MaterialCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Map")
                    .font(.headline)
                    .foregroundColor(.primary)
                MapSelectionView(coordinate: $coordinate)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                if let coord = coordinate {
                    Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text("Long-press on the map or search above to drop a pin.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var actionsCard: some View {
        MaterialCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Actions")
                    .font(.headline)
                    .foregroundColor(.primary)
                HStack(spacing: 12) {
                    Button(action: simulate) {
                        Label("Simulate", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAppStoreBuild || coordinate == nil || !pairingExists)

                    Button(action: clear) {
                        Label("Clear", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAppStoreBuild || !pairingExists)
                }
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(statusIsError ? .red : .green)
                }
                Text("Device IP: \(deviceIP)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        MKLocalSearch(request: request).start { response, _ in
            let items = response?.mapItems ?? []
            searchResults = items.map { item in
                SearchResult(
                    name: item.name ?? "Unknown",
                    subtitle: item.placemark.title ?? "",
                    item: item
                )
            }
        }
    }

    private func select(result: SearchResult) {
        coordinate = result.item.placemark.coordinate
        statusMessage = ""
        searchResults = []
        searchQuery = result.name
    }

    private func simulate() {
        guard pairingExists else {
            statusMessage = "Pairing file missing."
            statusIsError = true
            return
        }
        guard let coord = coordinate else { return }
        let code = simulate_location(deviceIP, coord.latitude, coord.longitude, pairingFilePath)
        if code == 0 {
            statusMessage = "Simulation running…"
            statusIsError = false
            showKeepOpenAlert = true
            beginBackgroundTask()
            startResendLoop()
        } else {
            statusMessage = "Simulation failed (code \(code))."
            statusIsError = true
            stopResendLoop()
            endBackgroundTask()
        }
    }

    private func clear() {
        guard pairingExists else { return }
        let code = clear_simulated_location()
        statusMessage = code == 0 ? "Cleared simulation." : "Clear failed (code \(code))."
        statusIsError = code != 0
        showKeepOpenAlert = false
        stopResendLoop()
        endBackgroundTask()
    }
    
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LocationSimulation") {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func startResendLoop() {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            guard pairingExists, let coord = coordinate else { return }
            _ = simulate_location(deviceIP, coord.latitude, coord.longitude, pairingFilePath)
        }
    }

    private func stopResendLoop() {
        resendTimer?.invalidate()
        resendTimer = nil
    }
}

private struct SearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let item: MKMapItem
}
