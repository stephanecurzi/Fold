//
//  FoldApp.swift
//  Fold
//
//  Created by Stephane Curzi on 2026-03-15.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct FoldApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: FoldMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "com.example.item-document")
    }
}

struct FoldMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        FoldVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct FoldVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
