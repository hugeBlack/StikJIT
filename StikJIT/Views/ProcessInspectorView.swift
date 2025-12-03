//
//  ProcessInspectorView.swift
//  StikJIT
//
//  Created by Stephen on 11/3/25.
//

import SwiftUI

struct ProcessInspectorView: View {
    @StateObject private var viewModel = ProcessInspectorViewModel()
    @Environment(\.themeExpansionManager) private var themeExpansion
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @State private var killCandidate: ProcessInfoEntry?
    @State private var killConfirmTask: Task<Void, Never>?
    
    private var backgroundStyle: BackgroundStyle {
        themeExpansion?.backgroundStyle(for: appThemeRaw) ?? AppTheme.system.backgroundStyle
    }
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(style: backgroundStyle)
                    .ignoresSafeArea()
                content
            }
            .navigationTitle("Process Inspector")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: viewModel.refresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                }
            }
        }
        .task {
            await viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .alert(item: $viewModel.killAlert) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                Button("Try Again") {
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    statsCard
                    processesCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .refreshable {
                viewModel.refresh()
            }
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always))
        }
    }
}

private extension ProcessInspectorView {
    var statsCard: some View {
        MaterialCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overview")
                    .font(.headline)
                    .foregroundColor(.primary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Processes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(viewModel.processes.count)")
                                .font(.title2.bold())
                        }
                        Spacer()
                    }
                }
            }
        }
    }
    
    var processesCard: some View {
        MaterialCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Processes")
                    .font(.headline)
                    .foregroundColor(.primary)
                if viewModel.filteredProcesses.isEmpty {
                    Text("No matching processes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.filteredProcesses) { process in
                            ProcessRow(
                                process: process,
                                isKilling: viewModel.killingPID == process.pid,
                                isConfirming: killCandidate?.pid == process.pid,
                                onKillTap: { handleKillTap(for: $0) }
                            )
                            .padding(.vertical, 10)
                            
                            if process.id != viewModel.filteredProcesses.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
            }
        }
    }
    
    func handleKillTap(for process: ProcessInfoEntry) {
        if killCandidate?.pid == process.pid {
            killConfirmTask?.cancel()
            killConfirmTask = nil
            killCandidate = nil
            viewModel.kill(process: process)
        } else {
            killCandidate = process
            killConfirmTask?.cancel()
            killConfirmTask = Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    if killCandidate?.pid == process.pid {
                        killCandidate = nil
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct ProcessRow: View {
    let process: ProcessInfoEntry
    let isKilling: Bool
    let isConfirming: Bool
    let onKillTap: (ProcessInfoEntry) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(process.displayName)
                    .font(.headline)
                Spacer()
                Text("PID \(process.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let bundle = process.bundleID, !bundle.isEmpty {
                Text(bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(process.executablePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Spacer()
                if isKilling {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.accentColor)
                } else {
                    Button {
                        onKillTap(process)
                    } label: {
                        if isConfirming {
                            Label("Confirm", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                        } else {
                            Image(systemName: "xmark.circle")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(isConfirming ? .green : .red)
                    .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - View Model

@MainActor
final class ProcessInspectorViewModel: ObservableObject {
    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
    
    @Published private(set) var processes: [ProcessInfoEntry] = []
    @Published var searchText: String = ""
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published private(set) var killingPID: Int?
    @Published var killAlert: AlertInfo?
    
    private var refreshTask: Task<Void, Never>?
    private var killTimeoutTask: Task<Void, Never>?
    @Published private(set) var lastUpdated: Date?
    var filteredProcesses: [ProcessInfoEntry] {
        guard !searchText.isEmpty else { return processes }
        return processes.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            ($0.bundleID?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            $0.executablePath.localizedCaseInsensitiveContains(searchText) ||
            "\($0.pid)".contains(searchText)
        }
    }
    
    var lastUpdatedText: String {
        guard let date = lastUpdated else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func startAutoRefresh() async {
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { break }
                await MainActor.run {
                    self.refresh()
                }
            }
        }
    }
    
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        killTimeoutTask?.cancel()
        killTimeoutTask = nil
    }
    
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        Task.detached(priority: .utility) { [weak self] in
            var err: NSError?
            let entries = FetchDeviceProcessList(&err) ?? []
            await MainActor.run {
                guard let self else { return }
                if let err {
                    self.errorMessage = err.localizedDescription
                } else {
                    self.processes = entries.compactMap { item -> ProcessInfoEntry? in
                        guard let dict = item as? NSDictionary else { return nil }
                        return ProcessInfoEntry(dictionary: dict)
                    }
                    self.lastUpdated = Date()
                }
                self.isRefreshing = false
            }
        }
    }
    
    func kill(process: ProcessInfoEntry) {
        guard killingPID == nil else {
            killAlert = AlertInfo(title: "Busy", message: "Already terminating PID \(killingPID!).")
            return
        }
        let targetPID = process.pid
        killingPID = targetPID
        killTimeoutTask?.cancel()
        killTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                guard let self else { return }
                if self.killingPID == targetPID {
                    self.killingPID = nil
                    self.killAlert = AlertInfo(
                        title: "Kill Timed Out",
                        message: "Could not confirm termination for PID \(targetPID). Try again."
                    )
                }
            }
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            var err: NSError?
            let success = KillDeviceProcess(Int32(targetPID), &err)
            await MainActor.run {
                guard let self else { return }
                self.killTimeoutTask?.cancel()
                self.killTimeoutTask = nil
                guard self.killingPID == targetPID else { return }
                self.killingPID = nil
                if success {
                    self.killAlert = AlertInfo(
                        title: "Process Terminated",
                        message: "PID \(targetPID) was terminated."
                    )
                    self.refresh()
                } else {
                    self.killAlert = AlertInfo(
                        title: "Kill Failed",
                        message: err?.localizedDescription ?? "Unknown error"
                    )
                }
            }
        }
    }
    
}

struct ProcessInfoEntry: Identifiable {
    let pid: Int
    private let rawPath: String
    let bundleID: String?
    let name: String?
    
    init?(dictionary: NSDictionary) {
        guard let pidNumber = dictionary["pid"] as? NSNumber else { return nil }
        pid = pidNumber.intValue
        rawPath = dictionary["path"] as? String ?? "Unknown"
        bundleID = dictionary["bundleID"] as? String
        name = dictionary["name"] as? String
    }
    
    var id: Int { pid }
    
    var executablePath: String {
        rawPath.replacingOccurrences(of: "file://", with: "")
    }
    
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        if let bundle = bundleID, !bundle.isEmpty {
            return bundle
        }
        let cleaned = executablePath
        if let component = cleaned.split(separator: "/").last {
            return String(component)
        }
        return "Process \(pid)"
    }
}
