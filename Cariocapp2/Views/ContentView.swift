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
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    case .game(let gameID):
                        GameView(gameID: gameID)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    case .gameCompletion(let gameID):
                        GameCompletionView(gameID: gameID)
                            .transition(.opacity)
                    case .players:
                        PlayerManagementView()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    case .rules:
                        RulesView()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    case .statistics:
                        StatisticsView()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    case .gameHistory:
                        GameHistoryView()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
        }
        .sheet(item: $coordinator.presentedSheet) { sheet in
            NavigationStack {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    switch sheet {
                    case .scoreEntry(let gameID):
                        ScoreEntryView(gameID: gameID)
                            .environmentObject(coordinator)
                    case .gameMenu(let gameID):
                        GameMenuView(gameID: gameID)
                            .environmentObject(coordinator)
                    case .gameCompletion(let gameID):
                        GameCompletionView(gameID: gameID)
                            .environmentObject(coordinator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .presentationDetents([.height(500)])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(true)
        }
        .environmentObject(coordinator)
        .onAppear {
            coordinator.updateContext(viewContext)
            
            // Configure global animation settings
            UIView.appearance().tintAdjustmentMode = .normal
            
            // Configure navigation bar appearance
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
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
