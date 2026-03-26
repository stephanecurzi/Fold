import SwiftUI

struct InlineFileView: View {
    let url: URL
    @Binding var content: String
    @Binding var activeTag: String?

    @Environment(PreferencesStore.self) var prefs
    @Environment(TagStore.self) var tagStore

    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            CenteredEditorView(
                text: $content,
                maxWidth: 780,
                activeTag: activeTag,
                preferences: prefs,
                fontSize: prefs.fontSize,
                fontName: prefs.fontName,
                tagColors: tagStore.tagColors,
                tagColorProvider: { tagStore.color(for: $0) }
            )

            if let tag = activeTag {
                ActiveTagPill(
                    tag: tag,
                    color: tagStore.swiftUIColor(for: tag)
                ) {
                    withAnimation(.spring(duration: 0.3)) { activeTag = nil }
                }
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.3), value: activeTag)
        .onAppear       { load() }
        .onChange(of: url) { _, _ in load() }
        .onChange(of: content) { _, new in
            guard isLoaded else { return }
            scheduleSave(new)
        }
    }

    // MARK: - Chargement

    private func load() {
        isLoaded = false
        activeTag = nil
        _ = url.startAccessingSecurityScopedResource()
        content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Active isLoaded au prochain cycle pour ne pas déclencher une sauvegarde immédiate
        DispatchQueue.main.async { isLoaded = true }
    }

    // MARK: - Sauvegarde différée (500 ms après la dernière frappe)

    private func scheduleSave(_ text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

