import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var coordinator = NavigationCoordinator(viewContext: NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType))
    
    var body: some View {
        NavigationStack(path: $coordinator.path) {
            MainMenuView()
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .newGame:
                        NewGameView()
                    case .game(let gameID):
                        GameView(gameID: gameID)
                    case .gameCompletion(let gameID):
                        GameCompletionView(gameID: gameID)
                    case .players:
                        PlayerManagementView()
                    case .rules:
                        RulesView()
                    case .statistics:
                        StatisticsView()
                    case .gameHistory:
                        GameHistoryView()
                    }
                }
        }
        .sheet(item: $coordinator.presentedSheet) { (sheet: AppSheet) in
            NavigationStack {
                switch sheet {
                case .scoreEntry(let gameID):
                    ScoreEntryView(gameID: gameID)
                case .gameMenu(let gameID):
                    GameMenuView(gameID: gameID)
                case .gameCompletion(let gameID):
                    GameCompletionView(gameID: gameID)
                }
            }
        }
        .environmentObject(coordinator)
        .onAppear {
            coordinator.updateContext(viewContext)
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let appState = AppState(viewContext: context)
        
        ContentView()
            .environment(\.managedObjectContext, context)
            .environmentObject(appState)
            .previewDisplayName("Main Menu")
    }
} 
