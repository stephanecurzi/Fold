import SwiftUI

struct InlineFileView: View {
    let url: URL
    @Binding var content: String
    @Binding var activeTag: String?

    @Environment(PreferencesStore.self) var prefs
    @Environment(TagStore.self) var tagStore

    @State private var isLoaded  = false
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var focusedTitle: String? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            CenteredEditorView(
                text: $content,
                maxWidth: 780,
                activeTag: activeTag,
                preferences: prefs,
                fontSize: prefs.fontSize,
                fontName: prefs.fontName,
                tagColors: tagStore.tagColors,
                tagColorProvider: { tagStore.color(for: $0) },
                focusedTitle: $focusedTitle
            )

            if let title = focusedTitle {
                ConcentrationPill(title: title) { focusedTitle = nil }
                    .padding(.top, 16)
                    .padding(.leading, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topLeading)))
                    .zIndex(2)
            }

            if let tag = activeTag {
                VStack {
                    Spacer()
                    ActiveTagPill(
                        tag: tag,
                        color: tagStore.swiftUIColor(for: tag)
                    ) {
                        withAnimation(.spring(duration: 0.3)) { activeTag = nil }
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: focusedTitle)
        .animation(.spring(duration: 0.3), value: activeTag)
        .onAppear { load(url) }
        .onChange(of: url) { old, new in
            // Sauvegarde le fichier précédent immédiatement avant de charger le nouveau
            flushSave(for: old)
            load(new)
        }
        .onChange(of: content) { _, new in
            guard isLoaded else { return }
            scheduleSave(new, to: url)
        }
    }

    // MARK: - Chargement

    private func load(_ target: URL) {
        isLoaded = false
        activeTag = nil
        _ = target.startAccessingSecurityScopedResource()
        content = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        DispatchQueue.main.async { isLoaded = true }
    }

    // MARK: - Sauvegarde différée (500 ms après la dernière frappe)

    private func scheduleSave(_ text: String, to target: URL) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            // Si le fichier est déjà ouvert comme NSDocument, on ne touche pas
            // au disque directement — AppKit gère sa propre sauvegarde et toute
            // écriture concurrente déclencherait l'alerte "changed by another app".
            guard NSDocumentController.shared.document(for: target) == nil else { return }
            try? text.write(to: target, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Sauvegarde immédiate (avant changement de fichier)

    private func flushSave(for target: URL) {
        saveTask?.cancel()
        saveTask = nil
        // Même garde : pas d'écriture directe si AppKit possède déjà ce fichier.
        guard NSDocumentController.shared.document(for: target) == nil else { return }
        try? content.write(to: target, atomically: true, encoding: .utf8)
    }
}



