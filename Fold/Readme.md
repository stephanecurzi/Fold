# Fold

Une application d'écriture minimaliste pour macOS, conçue comme successeur moderne de FoldingText.

Fold te permet d'écrire en Markdown sans voir la syntaxe. Les titres, la mise en forme et les liens sont rendus directement dans l'éditeur, en gardant le focus sur le texte.

---

## Fonctionnalités

- **Rendu Markdown en direct** — syntaxe masquée à la frappe (titres, gras, italique, code, listes, liens, surlignage, tâches…)
- **Système @tags** — ajoute `@tag` en fin de ligne pour coloriser la ligne. Les tags apparaissent dans la barre latérale et permettent de filtrer le document
- **Navigateur de dossiers** — ouvre des dossiers locaux et accède à tous tes fichiers texte depuis la barre latérale
- **Recherche & remplacement** — barre de recherche native (⌘F) avec remplacement simple ou global
- **Préférences typographiques** — choix de la police et de la taille de base (⌘,)
- **Menu Format complet** — raccourcis clavier pour toutes les opérations Markdown courantes

---

## Format de fichiers

Fold lit et écrit du texte brut UTF-8. Extensions supportées : `.md`, `.txt`, `.markdown`, `.rst`, `.fountain`, `.org` et plus. Aucun format propriétaire.

---

## Prérequis

- macOS 14 Sonoma ou plus récent
- Xcode 16+ pour compiler depuis les sources

---

## Structure du projet

```
Fold/
├── FoldApp.swift              # Point d'entrée, menus, notifications
├── FoldDocument.swift         # Lecture / écriture des fichiers
├── ContentView.swift          # Vue racine
├── TextEditorView.swift       # Éditeur centré
├── MarkdownEditorView.swift   # Wrapper NSViewRepresentable
├── MarkdownTextStorage.swift  # Moteur de coloration Markdown
├── SidebarView.swift          # Dossiers, étiquettes, color picker
├── PreferencesView.swift      # Panneau de préférences
├── FolderStore.swift          # Gestion des dossiers
├── TagStore.swift             # Couleurs des @tags
├── PreferencesStore.swift     # Préférences typographiques
└── SearchStore.swift          # Recherche & remplacement
```

---

## Origine

Fold a été créé pour remplacer [FoldingText](http://www.foldingtext.com), un outil d'écriture macOS longtemps apprécié mais devenu incompatible avec les versions récentes de macOS. Même philosophie — texte brut, Markdown rendu en direct, organisation par tags — dans une app Swift native.

---

## Licence

MIT