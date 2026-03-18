import SwiftUI

@main
struct FoldApp: App {
    @State private var folderStore = FolderStore()
    @State private var tagStore    = TagStore()

    var body: some Scene {
        DocumentGroup(newDocument: { FoldDocument() }) { config in
            ContentView(document: config.document)
                .environment(folderStore)
                .environment(tagStore)
        }
    }
}
