import SwiftUI
import Combine
import UniformTypeIdentifiers

extension UTType {
    static let foldDocument = UTType(exportedAs: "com.fold.markdown", conformingTo: .plainText)
}

final class FoldDocument: ReferenceFileDocument, ObservableObject {

    static var readableContentTypes: [UTType] {
        [.foldDocument, .plainText,
         UTType(filenameExtension: "md")       ?? .plainText,
         UTType(filenameExtension: "txt")       ?? .plainText,
         UTType(filenameExtension: "text")      ?? .plainText,
         UTType(filenameExtension: "markdown")  ?? .plainText,
         UTType(filenameExtension: "fountain")  ?? .plainText,
         UTType(filenameExtension: "rst")       ?? .plainText,
         UTType(filenameExtension: "org")       ?? .plainText,
        ]
    }

    static var writableContentTypes: [UTType] {
        [.foldDocument, .plainText,
         UTType(filenameExtension: "md")  ?? .plainText,
         UTType(filenameExtension: "txt") ?? .plainText,
        ]
    }

    @Published var text: String

    init(text: String = "") {
        self.text = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.text = string
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = snapshot.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
