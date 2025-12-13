import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MiniToolListView: View {
    @StateObject private var store = MiniToolStore()
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var showDeleteConfirmation = false
    @State private var pendingDelete: MiniToolBundle?
    @State private var alertVisible = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @Environment(\.themeExpansionManager) private var themeExpansion
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundStyle: BackgroundStyle { themeExpansion?.backgroundStyle(for: appThemeRaw) ?? AppTheme.system.backgroundStyle }
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }

    private var filteredTools: [MiniToolBundle] {
        guard !searchText.isEmpty else { return store.tools }
        return store.tools.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(style: backgroundStyle)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerCard

                        if filteredTools.isEmpty {
                            emptyCard
                        } else {
                            ForEach(filteredTools) { tool in
                                toolRow(tool)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }

                if store.isBusy {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Working…")
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                }

                if alertVisible {
                    CustomErrorView(
                        title: alertTitle,
                        message: alertMessage,
                        onDismiss: { alertVisible = false },
                        messageType: .error
                    )
                }
            }
            .navigationTitle("Mini Tools")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: {
                        Label("Import", systemImage: "tray.and.arrow.down")
                    }
                }
            }
            .onAppear { store.refresh() }
            .onChange(of: store.lastError) { _, message in
                guard let message else { return }
                presentError(title: "Mini Tool", message: message)
                store.lastError = nil
            }
            .alert("Delete Mini Tool?", isPresented: $showDeleteConfirmation, presenting: pendingDelete) { tool in
                Button("Delete", role: .destructive) { delete(tool) }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { tool in
                Text("Delete \(tool.name)? This removes its files permanently.")
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType("com.stik.StikJIT.stiktool") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    store.importTool(from: url)
                case .failure(let error):
                    presentError(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
        .preferredColorScheme(preferredScheme)
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(spacing: 12) {
            TextField("Search tools…", text: $searchText)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            HStack(spacing: 12) {
                WideGlassyButton(title: "Import", systemImage: "tray.and.arrow.down") {
                    showImporter = true
                }
            }
        }
        .padding(20)
        .background(glassyBackground)
    }

    private func toolRow(_ tool: MiniToolBundle) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                MiniToolRunnerView(tool: tool)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundColor(.blue)
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(tool.url.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()

                NavigationLink {
                    MiniToolEditorView(tool: tool)
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    pendingDelete = tool
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
            .buttonStyle(.plain)

        }
        .padding(20)
        .background(glassyBackground)
        .contextMenu {
            Button { copy(tool.url.lastPathComponent) } label: {
                Label("Copy Name", systemImage: "doc.on.doc")
            }
            Button { copy(tool.url.path) } label: {
                Label("Copy Path", systemImage: "folder")
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Label("No mini tools found", systemImage: "shippingbox")
                .font(.subheadline.weight(.semibold))
            Text("Tap New or Import to add a tool.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(glassyBackground)
    }

    private var glassyBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: overlayColors()),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.32)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }

    private func overlayColors() -> [Color] {
        let colors: [Color]
        switch backgroundStyle {
        case .staticGradient(let palette):
            colors = palette
        case .animatedGradient(let palette, _):
            colors = palette
        case .blobs(_, let background):
            colors = background
        case .particles(let particle, let background):
            colors = background.isEmpty ? [particle, particle.opacity(0.4)] : background
        case .customGradient(let palette):
            colors = palette
        case .adaptiveGradient(let light, let dark):
            colors = colorScheme == .dark ? dark : light
        }
        if colors.count >= 2 { return colors }
        if let first = colors.first { return [first, first.opacity(0.6)] }
        return [Color.blue, Color.purple]
    }

    // MARK: - Actions

    private func delete(_ tool: MiniToolBundle) {
        store.delete(tool)
        if let error = store.lastError {
            presentError(title: "Delete Failed", message: error)
        }
    }

    private func presentError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        alertVisible = true
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
