//
//  ConsoleLogsView.swift
//  StikJIT
//
//  Created by neoarz on 3/29/25.
//

import SwiftUI
import UIKit

struct ConsoleLogsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var environmentAccentColor
    @StateObject private var logManager = LogManager.shared
    @StateObject private var systemLogStream = SystemLogStream()
    @State private var selectedConsoleTab: ConsoleTab = .idevice
    @State private var jitScrollView: ScrollViewProxy? = nil
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    
    @State private var showingCustomAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isError = false
    
    @State private var logCheckTimer: Timer? = nil
    
    @State private var isViewActive = false
    @State private var lastProcessedLineCount = 0
    @State private var isLoadingLogs = false
    @State private var jitIsAtBottom = true
    @State private var syslogIsAtBottom = true
    @State private var showingSyslogSpeedSelector = false
    private let appLogRefreshInterval: TimeInterval = 3.0
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @Environment(\.themeExpansionManager) private var themeExpansion
    private var backgroundStyle: BackgroundStyle { themeExpansion?.backgroundStyle(for: appThemeRaw) ?? AppTheme.system.backgroundStyle }
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }
    private let syslogIntervalOptions: [Double] = [0.0, 0.2, 0.5, 1.0, 1.5, 2.0]

    private var accentColor: Color {
        themeExpansion?.resolvedAccentColor(from: customAccentColorHex) ?? .blue
    }

    private var overlayOpacity: Double {
        colorScheme == .dark ? 0.82 : 0.9
    }

    var body: some View {
        NavigationView {
            ZStack {
                ThemedBackground(style: backgroundStyle)
                    .ignoresSafeArea()
                Color(colorScheme == .dark ? .black : .white)
                    .opacity(overlayOpacity)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if selectedConsoleTab == .syslog {
                        syslogBetaTag
                    }

                    Group {
                        if selectedConsoleTab == .idevice {
                            jitLogsPane
                        } else {
                            syslogLogsPane
                        }
                    }

                    Spacer(minLength: 0)

                    Group {
                        if selectedConsoleTab == .idevice {
                            jitFooter
                        } else {
                            syslogFooter
                        }
                    }
                }
                .padding(.top, 12)
                .navigationBarTitleDisplayMode(.inline)
            }
            .overlay(
                Group {
                    if showingCustomAlert {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                            .overlay(
                                CustomErrorView(
                                    title: alertTitle,
                                    message: alertMessage,
                                    onDismiss: {
                                        showingCustomAlert = false
                                    },
                                    showButton: true,
                                    primaryButtonText: "OK",
                                    messageType: isError ? .error : .success
                                )
                            )
                    }
                    if showingSyslogSpeedSelector {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture { showingSyslogSpeedSelector = false }
                            .overlay(
                                appGlassCard {
                                    VStack(spacing: 18) {
                                        HStack {
                                            Text("Syslog Speed")
                                                .font(.title3.weight(.semibold))
                                            Spacer()
                                            Button {
                                                showingSyslogSpeedSelector = false
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Text("Choose how quickly new relay entries appear.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        VStack(spacing: 10) {
                                            ForEach(syslogIntervalOptions, id: \.self) { option in
                                                Button {
                                                    systemLogStream.updateInterval = option
                                                    showingSyslogSpeedSelector = false
                                                } label: {
                                                    HStack {
                                                        Text(intervalLabel(for: option))
                                                            .font(.headline)
                                                        Spacer()
                                                        if abs(systemLogStream.updateInterval - option) < 0.01 {
                                                            Image(systemName: "checkmark.circle.fill")
                                                                .foregroundColor(accentColor)
                                                        }
                                                    }
                                                    .padding(.horizontal, 18)
                                                    .frame(maxWidth: .infinity, minHeight: 44)
                                                }
                                                .buttonStyle(
                                                    GlassOvalButtonStyle(
                                                        height: 44,
                                                        strokeOpacity: abs(systemLogStream.updateInterval - option) < 0.01 ? 0.35 : 0.15
                                                    )
                                                )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 30)
                            )
                    }
                }
            )
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(preferredScheme)
        .onDisappear {
            systemLogStream.stop()
        }
    }
    
    private var jitLogsPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("=== DEVICE INFORMATION ===")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.vertical, 4)

                        Text("iOS Version: \(UIDevice.current.systemVersion)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Device: \(UIDevice.current.name)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Model: \(UIDevice.current.model)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("=== LOG ENTRIES ===")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    ForEach(logManager.logs) { logEntry in
                        Text(AttributedString(createLogAttributedString(logEntry)))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                            .padding(.horizontal, 4)
                            .id(logEntry.id)
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("jitScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "jitScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                jitIsAtBottom = offset > -20
            }
            .onChange(of: logManager.logs.count) { _ in
                guard jitIsAtBottom, let lastLog = logManager.logs.last else { return }
                withAnimation {
                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                }
            }
            .onAppear {
                jitScrollView = proxy
                isViewActive = true
                Task { await loadIdeviceLogsAsync() }
                startLogCheckTimer()
            }
            .onDisappear {
                isViewActive = false
                stopLogCheckTimer()
            }
        }
    }
    
    private var syslogLogsPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(systemLogStream.entries) { entry in
                        Text(AttributedString(createSyslogAttributedString(entry)))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                            .padding(.horizontal, 4)
                            .id(entry.id)
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("syslogScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "syslogScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                syslogIsAtBottom = offset > -20
            }
            .onChange(of: systemLogStream.entries.count) { _ in
                guard syslogIsAtBottom, let lastLog = systemLogStream.entries.last else { return }
                withAnimation {
                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                }
            }
            .onAppear {
                if selectedConsoleTab == .syslog && !systemLogStream.isStreaming {
                    systemLogStream.start()
                }
            }
            .onDisappear {
                systemLogStream.stop()
            }
        }
    }

    private var jitFooter: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .foregroundColor(.red)
                Text("\(logManager.errorCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)

            Button {
                Task { await loadIdeviceLogsAsync() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Refresh app logs")

            Button {
                logManager.clearLogs()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Clear app logs")

            Button {
                var logsContent = "=== DEVICE INFORMATION ===\n"
                logsContent += "Version: \(UIDevice.current.systemVersion)\n"
                logsContent += "Name: \(UIDevice.current.name)\n"
                logsContent += "Model: \(UIDevice.current.model)\n"
                logsContent += "StikJIT Version: App Version: 1.0\n\n"
                logsContent += "=== LOG ENTRIES ===\n"

                logsContent += logManager.logs.map {
                    "[\(formatTime(date: $0.timestamp))] [\($0.type.rawValue)] \($0.message)"
                }.joined(separator: "\n")

                UIPasteboard.general.string = logsContent

                alertTitle = "Logs Copied"
                alertMessage = "Logs have been copied to clipboard."
                isError = false
                showingCustomAlert = true
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Copy app logs")

            exportControl

            Button {
                selectedConsoleTab = .syslog
            } label: {
                Image(systemName: "rectangle.2.swap")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Switch to syslog relay")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var syslogFooter: some View {
        VStack(spacing: 10) {
            if let error = systemLogStream.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.small)
                        .foregroundColor(.red)
                    Text("\(syslogErrorCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: toggleSyslogPlayback) {
                    Image(systemName: syslogControlIcon)
                        .foregroundColor(accentColor)
                }
                .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
                .accessibilityLabel(syslogControlLabel)

                Button(action: { systemLogStream.clear() }) {
                    Image(systemName: "trash")
                        .foregroundColor(accentColor)
                }
                .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
                .accessibilityLabel("Clear syslog entries")

                Button(action: copySyslogToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(accentColor)
                }
                .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
                .accessibilityLabel("Copy syslog entries")

                Button {
                    showingSyslogSpeedSelector.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(accentColor)
                }
                .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
                .accessibilityLabel("Adjust syslog speed")

                Button {
                    selectedConsoleTab = .idevice
                } label: {
                    Image(systemName: "rectangle.2.swap")
                        .foregroundColor(accentColor)
                }
                .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
                .accessibilityLabel("Switch to app logs")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var syslogBetaTag: some View {
        HStack(spacing: 10) {
            Label {
                Text("Syslogs")
                    .font(.headline.weight(.semibold))
            } icon: {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(accentColor)
            }

            Text("BETA")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundColor(accentColor)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(accentColor.opacity(0.45), lineWidth: 1)
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    @ViewBuilder
    private var exportControl: some View {
        let logURL: URL = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")
        if FileManager.default.fileExists(atPath: logURL.path) {
            ShareLink(
                item: logURL,
                preview: SharePreview("idevice_log.txt", image: Image(systemName: "doc.text"))
            ) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Export app logs")
        } else {
            Button {
                alertTitle = "Export Failed"
                alertMessage = "No idevice logs found"
                isError = true
                showingCustomAlert = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Export app logs")
        }
    }
    
    private func createLogAttributedString(_ logEntry: LogManager.LogEntry) -> NSAttributedString {
        let fullString = NSMutableAttributedString()
        
        let timestampString = "[\(formatTime(date: logEntry.timestamp))]"
        let timestampAttr = NSAttributedString(
            string: timestampString,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.gray : UIColor.darkGray]
        )
        fullString.append(timestampAttr)
        fullString.append(NSAttributedString(string: " "))
        
        let typeString = "[\(logEntry.type.rawValue)]"
        let typeColor = UIColor(colorForLogType(logEntry.type))
        let typeAttr = NSAttributedString(
            string: typeString,
            attributes: [.foregroundColor: typeColor]
        )
        fullString.append(typeAttr)
        fullString.append(NSAttributedString(string: " "))
        
        let messageAttr = NSAttributedString(
            string: logEntry.message,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black]
        )
        fullString.append(messageAttr)
        
        return fullString
    }

    private func createSyslogAttributedString(_ entry: SystemLogStream.Entry) -> NSAttributedString {
        let type = logType(for: entry.raw)
        let fullString = NSMutableAttributedString()

        let timestampString = "[\(DateFormatter.consoleLogsFormatter.string(from: entry.timestamp))]"
        fullString.append(NSAttributedString(
            string: timestampString,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.gray : UIColor.darkGray]
        ))
        fullString.append(NSAttributedString(string: " "))

        let typeAttr = NSAttributedString(
            string: "[\(type.rawValue)]",
            attributes: [.foregroundColor: UIColor(colorForLogType(type))]
        )
        fullString.append(typeAttr)
        fullString.append(NSAttributedString(string: " "))

        let messageAttr = NSAttributedString(
            string: entry.raw,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black]
        )
        fullString.append(messageAttr)

        return fullString
    }
    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func colorForLogType(_ type: LogManager.LogEntry.LogType) -> Color {
        switch type {
        case .info:
            return .green
        case .error:
            return .red
        case .debug:
            return accentColor
        case .warning:
            return .orange
        }
    }

    private func logType(for line: String) -> LogManager.LogEntry.LogType {
        let lowercase = line.lowercased()
        if lowercase.contains("error") {
            return .error
        } else if lowercase.contains("warning") {
            return .warning
        } else if lowercase.contains("debug") {
            return .debug
        } else {
            return .info
        }
    }

    private var syslogErrorCount: Int {
        systemLogStream.entries.reduce(0) { count, entry in
            count + (logType(for: entry.raw) == .error ? 1 : 0)
        }
    }

    private func intervalLabel(for value: Double) -> String {
        if value <= 0 {
            return "Live"
        }
        return "\(String(format: "%.1f", value))s"
    }
    
    private func loadIdeviceLogsAsync() async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true
        
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt").path
        
        guard FileManager.default.fileExists(atPath: logPath) else {
            await MainActor.run {
                logManager.addInfoLog("No idevice logs found (Restart the app to continue reading)")
                isLoadingLogs = false
            }
            return
        }
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)
            
            let maxLines = 500
            let startIndex = max(0, lines.count - maxLines)
            let recentLines = Array(lines[startIndex..<lines.count])
            
            lastProcessedLineCount = lines.count
            
            await MainActor.run {
                logManager.clearLogs()
                
                for line in recentLines {
                    if line.isEmpty { continue }
                    
                    if line.contains("=== DEVICE INFORMATION ===") ||
                       line.contains("Version:") ||
                       line.contains("Name:") ||
                       line.contains("Model:") ||
                       line.contains("=== LOG ENTRIES ===") {
                        continue
                    }
                    
                    if line.contains("ERROR") || line.contains("Error") {
                        logManager.addErrorLog(line)
                    } else if line.contains("WARNING") || line.contains("Warning") {
                        logManager.addWarningLog(line)
                    } else if line.contains("DEBUG") {
                        logManager.addDebugLog(line)
                    } else {
                        logManager.addInfoLog(line)
                    }
                }

                if jitIsAtBottom, let last = logManager.logs.last {
                    jitScrollView?.scrollTo(last.id, anchor: .bottom)
                }
            }
        } catch {
            await MainActor.run {
                logManager.addErrorLog("Failed to read idevice logs: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            isLoadingLogs = false
        }
    }
    
    private func startLogCheckTimer() {
        guard logCheckTimer == nil else { return }
        logCheckTimer = Timer.scheduledTimer(withTimeInterval: appLogRefreshInterval, repeats: true) { _ in
            if isViewActive {
                Task { await checkForNewLogs() }
            }
        }
        if let logCheckTimer {
            RunLoop.main.add(logCheckTimer, forMode: .common)
        }
    }
    
    private func checkForNewLogs() async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true
        
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt").path
        
        guard FileManager.default.fileExists(atPath: logPath) else {
            isLoadingLogs = false
            return
        }
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)
            
            if lines.count > lastProcessedLineCount {
                let newLines = Array(lines[lastProcessedLineCount..<lines.count])
                lastProcessedLineCount = lines.count
                
                await MainActor.run {
                    for line in newLines {
                        if line.isEmpty { continue }
                        
                        if line.contains("ERROR") || line.contains("Error") {
                            logManager.addErrorLog(line)
                        } else if line.contains("WARNING") || line.contains("Warning") {
                            logManager.addWarningLog(line)
                        } else if line.contains("DEBUG") {
                            logManager.addDebugLog(line)
                        } else {
                            logManager.addInfoLog(line)
                        }
                    }
                    
                    let maxLines = 500
                    if logManager.logs.count > maxLines {
                        let excessCount = logManager.logs.count - maxLines
                        logManager.removeOldestLogs(count: excessCount)
                    }

                    if jitIsAtBottom, let last = logManager.logs.last {
                        jitScrollView?.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        } catch {
            await MainActor.run {
                logManager.addErrorLog("Failed to read new logs: \(error.localizedDescription)")
            }
        }
        
        isLoadingLogs = false
    }
    
    private func stopLogCheckTimer() {
        logCheckTimer?.invalidate()
        logCheckTimer = nil
    }

    private func toggleSyslogPlayback() {
        if !systemLogStream.isStreaming {
            systemLogStream.start()
        } else {
            systemLogStream.togglePause()
        }
    }

    private func copySyslogToClipboard() {
        let content = systemLogStream.concatenatedLog()
        guard !content.isEmpty else {
            alertTitle = "Export Failed"
            alertMessage = "No syslog entries to copy."
            isError = true
            showingCustomAlert = true
            return
        }

        UIPasteboard.general.string = content
        alertTitle = "Logs Copied"
        alertMessage = "Latest syslog entries copied to clipboard."
        isError = false
        showingCustomAlert = true
    }

    private var syslogControlIcon: String {
        if !systemLogStream.isStreaming || systemLogStream.isPaused {
            return "play.fill"
        }
        return "pause.fill"
    }

    private var syslogControlLabel: String {
        if !systemLogStream.isStreaming {
            return "Start syslog relay"
        }
        return systemLogStream.isPaused ? "Resume syslog stream" : "Pause syslog stream"
    }

}

private struct GlassOvalButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var strokeOpacity: Double = 0.16
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: configuration.isPressed ? 4 : 10, x: 0, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct ConsoleLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleLogsView()
            .themeExpansionManager(ThemeExpansionManager(previewUnlocked: true))
    }
}

private enum ConsoleTab: Hashable {
    case idevice
    case syslog
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension DateFormatter {
    static let consoleLogsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
