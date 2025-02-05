import SwiftUI
import CoreData

struct MainMenuView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var repository: GameRepository
    
    init() {
        let repository = GameRepository(context: PersistenceController.shared.container.viewContext)
        self._repository = StateObject(wrappedValue: repository)
    }
    
    var body: some View {
        List {
            Section {
                // New Game Button
                Button {
                    navigationCoordinator.path.append(.newGame)
                } label: {
                    MenuButtonView(
                        title: "New Game",
                        subtitle: "Start a new game of Carioca",
                        icon: "plus.circle.fill",
                        color: .blue
                    )
                }
                
                // Resume Game Button
                if let activeGame = repository.activeGames.first {
                    Button {
                        navigationCoordinator.navigateToGame(activeGame.id)
                    } label: {
                        MenuButtonView(
                            title: "Resume Game",
                            subtitle: "Continue your last game",
                            icon: "play.circle.fill",
                            color: .green
                        )
                    }
                }
                
                // Player Management Button
                Button {
                    navigationCoordinator.path.append(.players)
                } label: {
                    MenuButtonView(
                        title: "Player Management",
                        subtitle: "Manage players and guests",
                        icon: "person.2.fill",
                        color: .orange
                    )
                }
                
                // Rules Button
                Button {
                    navigationCoordinator.path.append(.rules)
                } label: {
                    MenuButtonView(
                        title: "Rules",
                        subtitle: "Learn how to play Carioca",
                        icon: "book.fill",
                        color: .purple
                    )
                }
                
                // Game History Button
                Button {
                    navigationCoordinator.path.append(.gameHistory)
                } label: {
                    MenuButtonView(
                        title: "Game History",
                        subtitle: "View past games and statistics",
                        icon: "chart.bar.fill",
                        color: .red
                    )
                }
            }
        }
        .navigationTitle("Carioca")
        .onAppear {
            repository.updateContext(viewContext)
            repository.fetchActiveGames()
        }
    }
}

// MARK: - Menu Button View
private struct MenuButtonView: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Preview
struct MainMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = NavigationCoordinator(viewContext: context)
        
        NavigationStack {
            MainMenuView()
                .environment(\.managedObjectContext, context)
                .environmentObject(coordinator)
        }
    }
} 