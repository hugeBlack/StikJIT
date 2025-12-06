import SwiftUI
import CodeEditorView
import LanguageSupport

struct MiniToolEditorView: View {
    let tool: MiniToolBundle

    private enum Target: String, CaseIterable, Identifiable {
        case indexHTML = "index.html"
        case backgroundJS = "background.js"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .indexHTML: return "index.html"
            case .backgroundJS: return "background.js"
            }
        }
    }

    @State private var htmlContent: String = ""
    @State private var backgroundContent: String = ""
    @State private var selectedTarget: Target = .indexHTML
    @State private var position: CodeEditor.Position = .init()
    @State private var messages: Set<TextLocated<Message>> = []

    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeExpansionManager) private var themeExpansion

    private var backgroundStyle: BackgroundStyle { themeExpansion?.backgroundStyle(for: appThemeRaw) ?? AppTheme.system.backgroundStyle }
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }
    private var editorTheme: Theme {
        colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
    }

    var body: some View {
        ZStack {
            ThemedBackground(style: backgroundStyle)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Picker("File", selection: $selectedTarget) {
                    ForEach(Target.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .pickerStyle(.segmented)

                CodeEditor(
                    text: binding(for: selectedTarget),
                    position: $position,
                    messages: $messages,
                    language: .swift()
                )
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.codeEditorTheme, editorTheme)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
        .preferredColorScheme(preferredScheme)
        .tint(Color.white)
        .toolbar(.hidden, for: .tabBar)
    }

    private func binding(for target: Target) -> Binding<String> {
        switch target {
        case .indexHTML: return $htmlContent
        case .backgroundJS: return $backgroundContent
        }
    }

    private func load() {
        htmlContent = (try? String(contentsOf: tool.indexURL)) ?? ""
        backgroundContent = (try? String(contentsOf: tool.backgroundURL)) ?? ""
    }

    private func save() {
        try? htmlContent.write(to: tool.indexURL, atomically: true, encoding: .utf8)
        try? backgroundContent.write(to: tool.backgroundURL, atomically: true, encoding: .utf8)
        dismiss()
    }
}
