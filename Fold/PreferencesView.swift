import SwiftUI

struct PreferencesView: View {
    @Environment(PreferencesStore.self) var prefs

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
                        Text("Défaut (16 px)").tag(CGFloat(16))
                        Divider()
                        ForEach(sizes.filter { $0 != 16 }, id: \.self) { size in
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
        }
        .frame(width: 480, height: 420)
    }
}
