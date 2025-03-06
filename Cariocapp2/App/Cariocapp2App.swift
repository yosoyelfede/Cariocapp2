import SwiftUI
import CoreData

@main
struct Cariocapp2App: App {
    // MARK: - Properties
    @StateObject private var container = DependencyContainer.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Register value transformers
        ScoresDictionaryValueTransformer.register()
        
        // Configure logging
        print("🎮 App starting up")
        print("🎮 Transformer registered")
    }
    
    // MARK: - Body
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, container.provideManagedObjectContext())
                .environment(\.gameCoordinator, container.provideGameCoordinator())
                .environmentObject(container.provideStateManager())
                .task {
                    do {
                        try await handleAppLaunch()
                    } catch {
                        print("Failed to handle app launch: \(error)")
                        container.provideStateManager().setError(.stateRestorationFailed(error.localizedDescription))
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    Task {
                        try? await handlePhaseChange(from: scenePhase, to: newPhase)
                    }
                }
        }
    }
    
    // MARK: - App Lifecycle
    private func handleAppLaunch() async throws {
        print("🎮 Handling app launch")
        let stateManager = container.provideStateManager()
        await stateManager.restoreState()
    }
    
    private func handlePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) async throws {
        switch newPhase {
        case .active:
            print("App became active")
            try await container.provideResourceManager().checkResources()
        case .background:
            print("App entered background")
            try await container.handleAppBackground()
        case .inactive:
            print("App became inactive")
            try await container.handleAppResignActive()
        @unknown default:
            break
        }
    }
    
    // MARK: - Helper Methods
    private func verifyDataConsistency() async throws {
        let context = container.provideManagedObjectContext()
        
        // Verify relationships
        let fetchRequest = NSFetchRequest<Game>(entityName: "Game")
        let games = try context.fetch(fetchRequest)
        
        for game in games {
            // Check player relationships
            if game.playersArray.isEmpty {
                context.delete(game)
                continue
            }
            
            // Check round relationships
            if game.roundsArray.isEmpty {
                context.delete(game)
                continue
            }
            
            // Verify round scores
            for round in game.roundsArray {
                if round.scores == nil {
                    round.scores = [:]
                }
            }
        }
        
        // Save changes
        try context.save()
    }
} 