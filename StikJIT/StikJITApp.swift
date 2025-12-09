//
//  StikJITApp.swift
//  StikJIT
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI
import Network
import UniformTypeIdentifiers
import NetworkExtension

// Register default settings before the app starts
private func registerAdvancedOptionsDefault() {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    // Enable advanced options by default on iOS 19/26 and above
    let enabled = os.majorVersion >= 19
    UserDefaults.standard.register(defaults: ["enableAdvancedOptions": enabled])
    UserDefaults.standard.register(defaults: ["enablePiP": enabled])
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.txmOverride: false])
}

// MARK: - Welcome Sheet

struct WelcomeSheetView: View {
    var onDismiss: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @Environment(\.themeExpansionManager) private var themeExpansion
    
    private var accent: Color {
        themeExpansion?.resolvedAccentColor(from: customAccentColorHex) ?? .blue
    }
    
    var body: some View {
        ZStack {
            // Background now comes from global BackgroundContainer
            Color.clear.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Card container with glassy material and stroke
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text("Welcome!")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                        
                        // Intro
                        Text("Thanks for installing the app. This brief introduction will help you get started.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                        
                        // App description
                        VStack(alignment: .leading, spacing: 6) {
                            Label("On‑device debugger", systemImage: "bolt.shield.fill")
                                .foregroundColor(accent)
                                .font(.headline)
                            Text("StikDebug is an on‑device debugger designed specifically for self‑developed apps. It helps streamline testing and troubleshooting without sending any data to external servers.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // VPN explanation
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Why VPN permission?", systemImage: "lock.shield.fill")
                                .foregroundColor(accent)
                                .font(.headline)
                            Text("The next step will prompt you to allow VPN permissions. This is necessary for the app to function properly. The VPN configuration allows your device to securely connect to itself — nothing more. No data is collected or sent externally; everything stays on your device.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // Continue button
                        Button(action: { onDismiss?() }) {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(accent.contrastText())
                                .frame(height: 44)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(accent)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .padding(.top, 8)
                        .accessibilityIdentifier("welcome_continue_button")
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 12, x: 0, y: 4)
                    
                    // Footer version info for consistency
                    HStack {
                        Spacer()
                        Text("iOS \(UIDevice.current.systemVersion)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
        }
        // Inherit preferredColorScheme from BackgroundContainer (no local override)
    }
}

// MARK: - VPN Logger

class VPNLogger: ObservableObject {
    @Published var logs: [String] = []
    static var shared = VPNLogger()
    private init() {}
    
    func log(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("[\(fileName):\(line)] \(function): \(message)")
        #endif
        logs.append("\(message)")
    }
}

// MARK: - Tunnel Manager

class TunnelManager: ObservableObject {
    @Published var tunnelStatus: TunnelStatus = .disconnected
    static var shared = TunnelManager()
    
    private var vpnManager: NETunnelProviderManager?
    private var pendingStopRequest = false
    private var tunnelDeviceIp: String {
        UserDefaults.standard.string(forKey: "TunnelDeviceIP") ?? "10.7.0.0"
    }
    private var tunnelFakeIp: String {
        UserDefaults.standard.string(forKey: "TunnelFakeIP") ?? "10.7.0.1"
    }
    private var tunnelSubnetMask: String {
        UserDefaults.standard.string(forKey: "TunnelSubnetMask") ?? "255.255.255.0"
    }
    private var tunnelBundleId: String {
        Bundle.main.bundleIdentifier!.appending(".TunnelProv")
    }
    
    enum TunnelStatus: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case disconnecting = "Disconnecting"
        case error = "Error"
    }
    
    private init() {
        loadTunnelPreferences()
        NotificationCenter.default.addObserver(self, selector: #selector(statusDidChange(_:)), name: .NEVPNStatusDidChange, object: nil)
    }
    
    private func loadTunnelPreferences() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    VPNLogger.shared.log("Error loading preferences: \(error.localizedDescription)")
                    self.tunnelStatus = .error
                    return
                }
                if let managers = managers, !managers.isEmpty {
                    for manager in managers {
                        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
                           proto.providerBundleIdentifier == self.tunnelBundleId {
                            self.vpnManager = manager
                            self.updateTunnelStatus(from: manager.connection.status)
                            VPNLogger.shared.log("Loaded existing tunnel configuration")
                            break
                        }
                    }
                    if self.vpnManager == nil, let firstManager = managers.first {
                        self.vpnManager = firstManager
                        self.updateTunnelStatus(from: firstManager.connection.status)
                        VPNLogger.shared.log("Using existing tunnel configuration")
                    }
                    if self.pendingStopRequest, let manager = self.vpnManager {
                        VPNLogger.shared.log("Pending stop request detected during preference load")
                        self.stopVPN(with: manager)
                    }
                } else {
                    VPNLogger.shared.log("No existing tunnel configuration found")
                }
            }
        }
    }
    
    @objc private func statusDidChange(_ notification: Notification) {
        if let connection = notification.object as? NEVPNConnection {
            updateTunnelStatus(from: connection.status)
        }
    }
    
    private func updateTunnelStatus(from connectionStatus: NEVPNStatus) {
        DispatchQueue.main.async {
            switch connectionStatus {
            case .invalid, .disconnected:
                self.tunnelStatus = .disconnected
            case .connecting:
                self.tunnelStatus = .connecting
            case .connected:
                self.tunnelStatus = .connected
            case .disconnecting:
                self.tunnelStatus = .disconnecting
            case .reasserting:
                self.tunnelStatus = .connecting
            @unknown default:
                self.tunnelStatus = .error
            }
            VPNLogger.shared.log("VPN status updated: \(self.tunnelStatus.rawValue)")
            if connectionStatus == .connected && heartbeatStartPending {
                startHeartbeatInBackground()
            }
        }
    }
    
    private func createOrUpdateTunnelConfiguration(completion: @escaping (Bool) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            guard let self = self else { return completion(false) }
            if let error = error {
                VPNLogger.shared.log("Error loading preferences: \(error.localizedDescription)")
                return completion(false)
            }
            
            let manager: NETunnelProviderManager
            if let existingManagers = managers, !existingManagers.isEmpty {
                if let matchingManager = existingManagers.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId
                }) {
                    manager = matchingManager
                    VPNLogger.shared.log("Updating existing tunnel configuration")
                } else {
                    manager = existingManagers[0]
                    VPNLogger.shared.log("Using first available tunnel configuration")
                }
            } else {
                manager = NETunnelProviderManager()
                VPNLogger.shared.log("Creating new tunnel configuration")
            }
            
            manager.localizedDescription = "StikDebug"
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.tunnelBundleId
            proto.serverAddress = "StikDebug's Local Network Tunnel"
            manager.protocolConfiguration = proto
            manager.isOnDemandEnabled = true
            manager.isEnabled = true
            
            manager.saveToPreferences { [weak self] error in
                guard let self = self else { return completion(false) }
                DispatchQueue.main.async {
                    if let error = error {
                        VPNLogger.shared.log("Error saving tunnel configuration: \(error.localizedDescription)")
                        completion(false)
                        return
                    }
                    self.vpnManager = manager
                    VPNLogger.shared.log("Tunnel configuration saved successfully")
                    completion(true)
                }
            }
        }
    }
    
    func startVPN() {
        if let manager = vpnManager {
            startExistingVPN(manager: manager)
        } else {
            createOrUpdateTunnelConfiguration { [weak self] success in
                guard let self = self, success else { return }
                self.loadTunnelPreferences()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let manager = self.vpnManager {
                        self.startExistingVPN(manager: manager)
                    }
                }
            }
        }
    }
    
    private func startExistingVPN(manager: NETunnelProviderManager) {
        guard tunnelStatus == .disconnected || tunnelStatus == .error else {
            VPNLogger.shared.log("Ignoring VPN start; current status: \(tunnelStatus.rawValue)")
            return
        }
        tunnelStatus = .connecting
        let options: [String: NSObject] = [
            "TunnelDeviceIP": tunnelDeviceIp as NSObject,
            "TunnelFakeIP": tunnelFakeIp as NSObject,
            "TunnelSubnetMask": tunnelSubnetMask as NSObject
        ]
        do {
            try manager.connection.startVPNTunnel(options: options)
            VPNLogger.shared.log("Network tunnel start initiated")
        } catch {
            tunnelStatus = .error
            VPNLogger.shared.log("Failed to start tunnel: \(error.localizedDescription)")
        }
    }
    
    func stopVPN() {
        guard let manager = vpnManager else {
            pendingStopRequest = true
            loadTunnelPreferences()
            return
        }
        pendingStopRequest = false
        stopVPN(with: manager)
    }
    
    private func stopVPN(with manager: NETunnelProviderManager) {
        tunnelStatus = .disconnecting
        manager.connection.stopVPNTunnel()
        VPNLogger.shared.log("Network tunnel stop initiated")
    }
}

// MARK: - AccentColor Environment Key (leave available but unused)

struct AccentColorKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var accentColor: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

// MARK: - Helper Functions and Globals

let fileManager = FileManager.default

func httpGet(_ urlString: String, result: @escaping (String?) -> Void) {
    if let url = URL(string: urlString) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                result(nil)
                return
            }
            
            if let data = data, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("Response: \(httpResponse.statusCode)")
                    if let dataString = String(data: data, encoding: .utf8) {
                        result(dataString)
                    }
                } else {
                    print("Received non-200 status code: \(httpResponse.statusCode)")
                }
            }
        }
        task.resume()
    }
}

func UpdateRetrieval() -> Bool {
    var ver: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
    }
    let urlString = "https://raw.githubusercontent.com/0-Blu/StikJIT/refs/heads/main/version.txt"
    var res = false
    httpGet(urlString) { result in
        if let fc = result {
            if ver != fc {
                res = true
            }
        }
    }
    return res
}

// MARK: - DNS Checker

class DNSChecker: ObservableObject {
    @Published var appleIP: String?
    @Published var controlIP: String?
    @Published var dnsError: String?
    
    func checkDNS() {
        checkIfConnectedToWifi { [weak self] wifiConnected in
            guard let self = self else { return }
            if wifiConnected {
                let group = DispatchGroup()
                
                group.enter()
                self.lookupIPAddress(for: "gs.apple.com") { ip in
                    DispatchQueue.main.async {
                        self.appleIP = ip
                    }
                    group.leave()
                }
                
                group.enter()
                self.lookupIPAddress(for: "google.com") { ip in
                    DispatchQueue.main.async {
                        self.controlIP = ip
                    }
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    if self.controlIP == nil {
                        self.dnsError = "No internet connection."
                        print("Control host lookup failed, so no internet connection.")
                    } else if self.appleIP == nil {
                        self.dnsError = "Apple DNS blocked. Your network might be filtering Apple traffic."
                        print("Control lookup succeeded, but Apple lookup failed: likely blocked.")
                    } else {
                        self.dnsError = nil
                        print("DNS lookups succeeded: Apple -> \(self.appleIP!), Control -> \(self.controlIP!)")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.dnsError = nil
                    print("Not connected to WiFi; continuing without DNS check.")
                }
            }
        }
    }
    
    private func checkIfConnectedToWifi(completion: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { path in
            completion(path.status == .satisfied)
            monitor.cancel()
        }
        let queue = DispatchQueue.global(qos: .background)
        monitor.start(queue: queue)
    }
    
    private func lookupIPAddress(for host: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            var hints = addrinfo(
                ai_flags: 0,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var res: UnsafeMutablePointer<addrinfo>?
            let err = getaddrinfo(host, nil, &hints, &res)
            if err != 0 {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            var ipAddress: String?
            var ptr = res
            while ptr != nil {
                if let addr = ptr?.pointee.ai_addr {
                    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, ptr!.pointee.ai_addrlen,
                                   &hostBuffer, socklen_t(hostBuffer.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        ipAddress = String(cString: hostBuffer)
                        break
                    }
                }
                ptr = ptr?.pointee.ai_next
            }
            freeaddrinfo(res)
            DispatchQueue.main.async { completion(ipAddress) }
        }
    }
}

// MARK: - Main App

// Global state variable for the heartbeat response.
var pubHeartBeat = false
private var heartbeatStartPending = false
private var heartbeatStartInProgress = false

@main
struct HeartbeatApp: App {
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("autoStartVPN") private var autoStartVPN = true
    @State private var showWelcomeSheet: Bool = false
    @State private var show_alert = false
    @State private var alert_string = ""
    @State private var alert_title = ""
    @StateObject private var mount = MountingProgress.shared
    @StateObject private var themeExpansionManager = ThemeExpansionManager()
    @Environment(\.scenePhase) private var scenePhase   // Observe scene lifecycle
    
    init() {
        registerAdvancedOptionsDefault()
        newVerCheck()
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        // Initialize UIKit tint from stored accent at launch (defaults to blue until entitlements load)
        HeartbeatApp.updateUIKitTint(customHex: customAccentColorHex, hasAccess: false)
    }
    
    // Make this static so we can call it without capturing self in init
    private static func updateUIKitTint(customHex: String, hasAccess: Bool) {
        let color: UIColor
        if hasAccess, !customHex.isEmpty, let swiftColor = Color(hex: customHex) {
            color = UIColor(swiftColor)
        } else {
            color = .systemBlue
        }
        UIView.appearance().tintColor = color
    }
    
    func newVerCheck() {
        let currentDate = Calendar.current.startOfDay(for: Date())
        let VUA = UserDefaults.standard.object(forKey: "VersionUpdateAlert") as? Date ?? Date.distantPast
        
        if currentDate > Calendar.current.startOfDay(for: VUA) {
            if UpdateRetrieval() {
                alert_title = "Update Avaliable!"
                let urlString = "https://raw.githubusercontent.com/0-Blu/StikJIT/refs/heads/main/version.txt"
                httpGet(urlString) { result in
                    if result == nil { return }
                    alert_string = "Update to: version \(result!)!"
                    show_alert = true
                }
            }
            UserDefaults.standard.set(currentDate, forKey: "VersionUpdateAlert")
        }
    }
    
    private func triggerAutoVPNStartIfNeeded() {
        guard autoStartVPN, DeviceConnectionContext.requiresLoopbackVPN else { return }
        let manager = TunnelManager.shared
        if manager.tunnelStatus == .disconnected || manager.tunnelStatus == .error {
            manager.startVPN()
        }
    }
    
    private var globalAccent: Color {
        themeExpansionManager.resolvedAccentColor(from: customAccentColorHex)
    }
    
    var body: some Scene {
        WindowGroup {
            BackgroundContainer {
                MainTabView()
                    .onAppear {
                        Task {
                            let fileManager = FileManager.default
                            for item in ddiDownloadItems {
                                let destinationURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
                                if fileManager.fileExists(atPath: destinationURL.path) { continue }
                                do {
                                    try await downloadFile(from: item.urlString, to: destinationURL)
                                } catch {
                                    await MainActor.run {
                                        alert_title = "An Error has Occurred"
                                        alert_string = "[Download DDI Error]: \(error.localizedDescription)"
                                        show_alert = true
                                    }
                                    break
                                }
                            }
                        }
                    }
                    .overlay(
                        ZStack {
                            if show_alert {
                                CustomErrorView(
                                    title: alert_title,
                                    message: alert_string,
                                    onDismiss: {
                                        show_alert = false
                                    },
                                    showButton: true,
                                    primaryButtonText: "OK"
                                )
                            }
                        }
                    )
            }
            .themeExpansionManager(themeExpansionManager)
            // Apply global tint to all SwiftUI views in this window
            .tint(globalAccent)
            .onAppear {
                // On first launch, present the welcome sheet.
                // Otherwise, start the VPN automatically.
                if !hasLaunchedBefore {
                    showWelcomeSheet = true
                } else {
                    triggerAutoVPNStartIfNeeded()
                }
                HeartbeatApp.updateUIKitTint(customHex: customAccentColorHex,
                                             hasAccess: themeExpansionManager.hasThemeExpansion)
            }
            .onChange(of: themeExpansionManager.hasThemeExpansion) { hasAccess in
                HeartbeatApp.updateUIKitTint(customHex: customAccentColorHex, hasAccess: hasAccess)
            }
            .onChange(of: customAccentColorHex) { newHex in
                HeartbeatApp.updateUIKitTint(customHex: newHex,
                                             hasAccess: themeExpansionManager.hasThemeExpansion)
            }
            .sheet(isPresented: $showWelcomeSheet) {
                WelcomeSheetView {
                    // When the user taps "Continue", mark the app as launched and start the VPN if allowed.
                    hasLaunchedBefore = true
                    showWelcomeSheet = false
                    triggerAutoVPNStartIfNeeded()
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print("App became active – restarting heartbeat")
                startHeartbeatInBackground()
            }
        }
    }
}

// MARK: - Additional Helpers

actor FunctionGuard<T> {
    private var runningTask: Task<T, Never>?
    
    func execute(_ work: @escaping @Sendable () -> T) async -> T {
        if let task = runningTask {
            return await task.value
        }
        let task = Task.detached { work() }
        runningTask = task
        let result = await task.value
        runningTask = nil
        return result
    }
}

class MountingProgress: ObservableObject {
    static var shared = MountingProgress()
    @Published var mountProgress: Double = 0.0
    @Published var mountingThread: Thread?
    @Published var coolisMounted: Bool = false
    
    func checkforMounted() {
        DispatchQueue.global(qos: .utility).async {
            let mounted = isMounted()
            DispatchQueue.main.async {
                self.coolisMounted = mounted
            }
        }
    }
    
    func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
        let percentage = Double(progress) / Double(total) * 100.0
        print("Mounting progress: \(percentage)%")
        DispatchQueue.main.async {
            self.mountProgress = percentage
        }
    }
    
    func pubMount() {
        mount()
    }
    
    private func mount() {
        if DeviceConnectionContext.requiresLoopbackVPN {
            guard TunnelManager.shared.tunnelStatus == .connected else {
                DispatchQueue.main.async {
                    self.coolisMounted = false
                    self.mountingThread = nil
                }
                return
            }
        }
        
        let currentlyMounted = isMounted()
        DispatchQueue.main.async {
            self.coolisMounted = currentlyMounted
        }
        let pairingpath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        
        if isPairing(), !currentlyMounted {
            if let mountingThread = mountingThread {
                mountingThread.cancel()
                self.mountingThread = nil
            }
            
            mountingThread = Thread { [weak self] in
                guard let self = self else { return }
                let mountResult = mountPersonalDDI(
                    deviceIP: DeviceConnectionContext.targetIPAddress,
                    imagePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg").path,
                    trustcachePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path,
                    manifestPath: URL.documentsDirectory.appendingPathComponent("DDI/BuildManifest.plist").path,
                    pairingFilePath: pairingpath
                )
                
                DispatchQueue.main.async {
                    if mountResult != 0 {
                        showAlert(title: "Error", message: "An Error Occured when Mounting the DDI\nError Code: \(mountResult)", showOk: true, showTryAgain: true) { shouldTryAgain in
                            if shouldTryAgain {
                                self.mount()
                            }
                        }
                    } else {
                        self.coolisMounted = true
                        self.checkforMounted()
                    }
                    self.mountingThread = nil
                }
            }
            
            mountingThread!.qualityOfService = .background
            mountingThread!.name = "mounting"
            mountingThread!.start()
        }
    }
}

func isPairing() -> Bool {
    let pairingpath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
    var pairingFile: IdevicePairingFile?
    let err = idevice_pairing_file_read(pairingpath, &pairingFile)
    if let err {
        print("Failed to read pairing file: \(err.pointee.code)")
        if err.pointee.code == -9 {  // InvalidHostID is -9
            return false
        }
        return false
    }
    return true
}

func startHeartbeatInBackground(requireVPNConnection: Bool? = nil) {
    assert(Thread.isMainThread, "startHeartbeatInBackground must be called on the main thread")
    let pairingFileURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
    
    guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
        heartbeatStartPending = false
        return
    }
    
    let shouldRequireVPN = requireVPNConnection ?? DeviceConnectionContext.requiresLoopbackVPN
    let vpnConnected = TunnelManager.shared.tunnelStatus == .connected
    if shouldRequireVPN && !vpnConnected {
        if !heartbeatStartPending {
            print("Heartbeat start deferred until VPN connects")
        }
        heartbeatStartPending = true
        return
    }
    
    guard !heartbeatStartInProgress else {
        return
    }
    
    heartbeatStartPending = false
    heartbeatStartInProgress = true
    
    let heartBeatThread = Thread {
        defer {
            DispatchQueue.main.async {
                heartbeatStartInProgress = false
            }
        }
        let completionHandler: @convention(block) (Int32, String?) -> Void = { result, message in
            if result == 0 {
                print("Heartbeat started successfully: \(message ?? "")")
                pubHeartBeat = true
                
                if FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path) {
                    MountingProgress.shared.pubMount()
                }
            } else {
                print("Error: \(message ?? "") (Code: \(result))")
                DispatchQueue.main.async {
                    if result == -9 {
                        do {
                            try FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                            print("Removed invalid pairing file")
                        } catch {
                            print("Error removing invalid pairing file: \(error)")
                        }
                        
                        showAlert(
                            title: "Invalid Pairing File",
                            message: "The pairing file is invalid or expired. Please select a new pairing file.",
                            showOk: true,
                            showTryAgain: false,
                            primaryButtonText: "Select New File"
                        ) { _ in
                            NotificationCenter.default.post(name: NSNotification.Name("ShowPairingFilePicker"), object: nil)
                        }
                    } else {
                        showAlert(
                            title: "Heartbeat Error",
                            message: "Failed to connect to Heartbeat (\(result)). Are you connected to WiFi or is Airplane Mode enabled? Cellular data isn’t supported. Please launch the app at least once with WiFi enabled. After that, you can switch to cellular data to turn on the VPN, and once the VPN is active you can use Airplane Mode.",
                            showOk: false,
                            showTryAgain: true
                        ) { shouldTryAgain in
                            if shouldTryAgain {
                                DispatchQueue.main.async {
                                    startHeartbeatInBackground()
                                }
                            }
                        }
                    }
                }
            }
        }
        JITEnableContext.shared.startHeartbeat(completionHandler: completionHandler, logger: nil)
    }
    
    heartBeatThread.qualityOfService = .background
    heartBeatThread.name = "Heartbeat"
    heartBeatThread.start()
}

func checkVPNConnection(callback: @escaping (Bool, String?) -> Void) {
    let targetIP = DeviceConnectionContext.targetIPAddress
    let host = NWEndpoint.Host(targetIP)
    let port = NWEndpoint.Port(rawValue: 62078)!
    let connection = NWConnection(host: host, port: port, using: .tcp)
    var timeoutWorkItem: DispatchWorkItem?
    
    timeoutWorkItem = DispatchWorkItem { [weak connection] in
        if connection?.state != .ready {
            connection?.cancel()
            DispatchQueue.main.async {
                if timeoutWorkItem?.isCancelled == false {
                    let message: String
                    if DeviceConnectionContext.requiresLoopbackVPN {
                        message = "[TIMEOUT] The loopback VPN is not connected. Try closing this app, turn it off and back on."
                    } else {
                        message = "[TIMEOUT] Could not reach the device at \(targetIP). Make sure it’s online and on the same network."
                    }
                    callback(false, message)
                }
            }
        }
    }
    
    connection.stateUpdateHandler = { [weak connection] state in
        switch state {
        case .ready:
            timeoutWorkItem?.cancel()
            connection?.cancel()
            DispatchQueue.main.async {
                callback(true, nil)
            }
        case .failed(let error):
            timeoutWorkItem?.cancel()
            connection?.cancel()
            DispatchQueue.main.async {
                let message: String
                if DeviceConnectionContext.requiresLoopbackVPN {
                    if error == NWError.posix(.ETIMEDOUT) {
                        message = "The loopback VPN is not connected. Try closing the app, turn it off and back on."
                    } else if error == NWError.posix(.ECONNREFUSED) {
                        message = "Wi-Fi is not connected. StikDebug can't connect over cellular data while in loopback mode."
                    } else {
                        message = "VPN check error: \(error.localizedDescription)"
                    }
                } else {
                    message = "Could not reach the device at \(targetIP): \(error.localizedDescription)"
                }
                callback(false, message)
            }
        default:
            break
        }
    }
    
    connection.start(queue: .global())
    if let workItem = timeoutWorkItem {
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: workItem)
    }
}

public func showAlert(title: String, message: String, showOk: Bool, showTryAgain: Bool = false, primaryButtonText: String? = nil, messageType: MessageType = .error, completion: ((Bool) -> Void)? = nil) {
    DispatchQueue.main.async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        let rootViewController = scene.windows.first?.rootViewController
        if showTryAgain {
            let customErrorView = CustomErrorView(
                title: title,
                message: message,
                onDismiss: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(false)
                },
                showButton: true,
                primaryButtonText: primaryButtonText ?? "Try Again",
                onPrimaryButtonTap: {
                    completion?(true)
                },
                messageType: messageType
            )
            let hostingController = UIHostingController(rootView: customErrorView)
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.view.backgroundColor = .clear
            rootViewController?.present(hostingController, animated: true)
        } else if showOk {
            let customErrorView = CustomErrorView(
                title: title,
                message: message,
                onDismiss: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(true)
                },
                showButton: true,
                primaryButtonText: primaryButtonText ?? "OK",
                onPrimaryButtonTap: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(true)
                },
                messageType: messageType
            )
            let hostingController = UIHostingController(rootView: customErrorView)
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.view.backgroundColor = .clear
            rootViewController?.present(hostingController, animated: true)
        } else {
            let customErrorView = CustomErrorView(
                title: title,
                message: message,
                onDismiss: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(false)
                },
                showButton: false,
                messageType: messageType
            )
            let hostingController = UIHostingController(rootView: customErrorView)
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.view.backgroundColor = .clear
            rootViewController?.present(hostingController, animated: true)
        }
    }
}

private struct DDIDownloadItem {
    let name: String
    let relativePath: String
    let urlString: String
}

private let ddiDownloadItems: [DDIDownloadItem] = [
    .init(
        name: "Build Manifest",
        relativePath: "DDI/BuildManifest.plist",
        urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/BuildManifest.plist"
    ),
    .init(
        name: "Image",
        relativePath: "DDI/Image.dmg",
        urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg"
    ),
    .init(
        name: "TrustCache",
        relativePath: "DDI/Image.dmg.trustcache",
        urlString: "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache"
    )
]

enum DDIDownloadError: LocalizedError {
    case invalidURL(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let string):
            return "Invalid download URL: \(string)"
        }
    }
}

func downloadFile(from urlString: String, to destinationURL: URL) async throws {
    guard let url = URL(string: urlString) else {
        throw DDIDownloadError.invalidURL(urlString)
    }
    let (tempLocalUrl, _) = try await URLSession.shared.download(from: url)
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
    if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
    }
    try fileManager.moveItem(at: tempLocalUrl, to: destinationURL)
}

func redownloadDDI(progressHandler: ((Double, String) -> Void)? = nil) async throws {
    let fileManager = FileManager.default
    let totalStages = Double(ddiDownloadItems.count + 1)
    var completedStages = 0.0
    
    progressHandler?(0.0, "Removing existing DDI files…")
    for item in ddiDownloadItems {
        let fileURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    completedStages += 1.0
    progressHandler?(completedStages / totalStages, "Starting downloads…")
    
    for item in ddiDownloadItems {
        progressHandler?(completedStages / totalStages, "Downloading \(item.name)…")
        let destinationURL = URL.documentsDirectory.appendingPathComponent(item.relativePath)
        try await downloadFile(from: item.urlString, to: destinationURL)
        completedStages += 1.0
        progressHandler?(completedStages / totalStages, "\(item.name) ready")
    }
    progressHandler?(1.0, "DDI download complete.")
}
