import SwiftUI

struct PreferencesView: View {
    @Environment(PreferencesStore.self) var prefs
    @Environment(TagStore.self) var tagStore

    let sizes: [CGFloat] = [11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 26, 28, 32]

    var body: some View {
        @Bindable var prefs = prefs

        TabView {
            // ── Onglet Typographie ─────────────────────
            Form {
                Section("Police") {
                    Picker("Police de base", selection: $prefs.fontName) {
                        Text("Défaut (SF Pro Text)").tag("SF Pro Text")
                        Divider()
                        ForEach(prefs.availableFonts.filter { $0 != "SF Pro Text" }, id: \.self) { name in
                            Text(name).font(.custom(name, size: 14)).tag(name)
                        }
                    }

                    Picker("Taille de base", selection: $prefs.fontSize) {
                        Text("Défaut (18 px)").tag(CGFloat(18))
                        Divider()
                        ForEach(sizes.filter { $0 != 18 }, id: \.self) { size in
                            Text("\(Int(size)) px").tag(size)
                        }
                    }
                }

                Section("Aperçu") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Titre H1")
                            .font(Font(prefs.h1Font))
                            .foregroundStyle(.primary)
                        Text("Titre H2")
                            .font(Font(prefs.h2Font))
                            .foregroundStyle(.primary)
                        Text("Voici un exemple de texte de base. Il représente le rendu dans l'éditeur.")
                            .font(Font(prefs.bodyFont))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Typographie", systemImage: "textformat")
            }
            .tag("typo")

            // ── Onglet Étiquettes ──────────────────────
            TagPreferencesTab(tagStore: tagStore)
                .tabItem {
                    Label("Étiquettes", systemImage: "tag")
                }
                .tag("tags")
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - Onglet Étiquettes

struct TagPreferencesTab: View {
    let tagStore: TagStore

    var body: some View {
        Form {
            // ── Étiquettes par défaut ──
            Section {
                ForEach(tagStore.defaultTagNames, id: \.self) { tag in
                    TagPreferenceRow(tag: tag, tagStore: tagStore, isDefault: true)
                }
            } header: {
                Text("Étiquettes par défaut")
            } footer: {
                Text("Ces étiquettes sont intégrées à Fold. Vous pouvez changer leur couleur ou la réinitialiser.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            }

            // ── Étiquettes personnalisées ──
            if !tagStore.customTagNames.isEmpty {
                Section {
                    ForEach(tagStore.customTagNames, id: \.self) { tag in
                        TagPreferenceRow(tag: tag, tagStore: tagStore, isDefault: false)
                    }
                } header: {
                    Text("Étiquettes personnalisées")
                } footer: {
                    Text("Créées automatiquement lors de l'utilisation de @étiquette dans vos documents.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Ligne d'étiquette

struct TagPreferenceRow: View {
    let tag: String
    let tagStore: TagStore
    let isDefault: Bool

    @State private var showPicker = false
    @State private var showResetConfirm = false
    @State private var showDeleteConfirm = false

    private var isModified: Bool {
        guard let original = defaultTags[tag] else { return false }
        return tagStore.tagColors[tag] != original
    }

    var body: some View {
        HStack(spacing: 10) {
            // Pastille couleur — ouvre le sélecteur
            Circle()
                .fill(tagStore.swiftUIColor(for: tag))
                .frame(width: 14, height: 14)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .onTapGesture { showPicker = true }
                .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                    TagColorPicker(tag: tag, tagStore: tagStore)
                }

            // Nom
            Text("@\(tag)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)

            Spacer()

            // Badge "défaut" si non modifié
            if isDefault && !isModified {
                Text("défaut")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            // Bouton réinitialiser (étiquettes par défaut modifiées)
            if isDefault && isModified {
                Button {
                    showResetConfirm = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Réinitialiser la couleur d'origine")
                .alert(
                    "Réinitialiser « \(tag) » ?",
                    isPresented: $showResetConfirm
                ) {
                    Button("Réinitialiser") {
                        tagStore.resetToDefault(tag)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Annuler", role: .cancel) {}
                } message: {
                    Text("La couleur reviendra à sa valeur d'origine.")
                }
            }

            // Bouton supprimer (étiquettes personnalisées)
            if !isDefault {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Supprimer cette étiquette")
                .alert(
                    "Supprimer « \(tag) » ?",
                    isPresented: $showDeleteConfirm
                ) {
                    Button("Supprimer") {
                        tagStore.removeTag(tag)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Annuler", role: .cancel) {}
                } message: {
                    Text("L'étiquette sera retirée de la liste, mais pas de vos documents.")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

