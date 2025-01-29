//
//  Cariocapp2App.swift
//  Cariocapp2
//
//  Created by Federico Antunovic on 29-01-25.
//

import SwiftUI

@main
struct Cariocapp2App: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
