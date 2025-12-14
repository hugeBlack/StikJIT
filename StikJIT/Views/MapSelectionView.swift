//
//  MapSelectionView.swift
//  StikJIT
//
//  Created by Stephen on 11/3/25.
//

import SwiftUI
import MapKit
import UIKit
import Pipify

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

final class LocationSpoofingPiPState: ObservableObject {
    @Published var status: String = "Idle"
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var lastUpdated: Date?
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
    @AppStorage("enablePiP") private var enablePiP = true
    @State private var pipPresented = false
    @StateObject private var pipState = LocationSpoofingPiPState()

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
        let docPathUrl = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let currentDeviceUUIDStr = UserDefaults.standard.string(forKey: "DeviceLibraryActiveDeviceID")

        let pairingFileURL: URL
        if let uuid = currentDeviceUUIDStr,
           uuid != "00000000-0000-0000-0000-000000000001" {

            pairingFileURL = docPathUrl.appendingPathComponent(
                "DeviceLibrary/Pairings/\(uuid).mobiledevicepairing"
            )
        } else {
            pairingFileURL = docPathUrl.appendingPathComponent("pairingFile.plist")
        }
        
        return pairingFileURL.path()
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
                dismissPiPSession()
            }
            .onChange(of: enablePiP) { _, newValue in
                if !newValue {
                    pipPresented = false
                }
            }
        }
        .pipify(isPresented: Binding(
            get: { pipPresented && enablePiP },
            set: { pipPresented = $0 }
        )) {
            LocationSpoofingPiPView(state: pipState)
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
            recordPiPEvent(status: "Simulating…", coordinate: coord)
        } else {
            statusMessage = "Simulation failed (code \(code))."
            statusIsError = true
            stopResendLoop()
            endBackgroundTask()
            dismissPiPSession()
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
        if code == 0 {
            recordPiPEvent(status: "Simulation cleared", coordinate: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                dismissPiPSession()
            }
        } else {
            dismissPiPSession()
        }
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
            guard self.pairingExists, let coord = self.coordinate else { return }
            _ = simulate_location(self.deviceIP, coord.latitude, coord.longitude, self.pairingFilePath)
            self.recordPiPEvent(status: "Location refreshed", coordinate: coord)
        }
        if let coord = coordinate {
            recordPiPEvent(status: "Simulating…", coordinate: coord)
        }
    }

    private func stopResendLoop() {
        resendTimer?.invalidate()
        resendTimer = nil
    }
    
    private func recordPiPEvent(status: String, coordinate: CLLocationCoordinate2D?) {
        DispatchQueue.main.async {
            pipState.status = status
            pipState.coordinate = coordinate
            pipState.lastUpdated = Date()
            pipPresented = true
        }
    }

    private func dismissPiPSession() {
        DispatchQueue.main.async {
            pipPresented = false
            pipState.lastUpdated = nil
            pipState.coordinate = nil
        }
    }
}

private struct SearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let item: MKMapItem
}

private struct LocationSpoofingPiPView: View {
    @ObservedObject var state: LocationSpoofingPiPState
    
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    private var coordinateText: String? {
        guard let coordinate = state.coordinate else { return nil }
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
    
    private var lastUpdatedText: String? {
        guard let lastUpdated = state.lastUpdated else { return nil }
        let label = Self.relativeFormatter.localizedString(for: lastUpdated, relativeTo: Date())
        return "Last send \(label)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.status)
                .font(.headline)
                .foregroundColor(.white)
            if let coordinateText {
                Text(coordinateText)
                    .font(.subheadline.monospaced())
                    .foregroundColor(.white.opacity(0.9))
            }
            if let lastUpdatedText {
                Text(lastUpdatedText)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            Text("Location Spoofing")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .frame(width: 280, height: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.65))
        )
    }
}
