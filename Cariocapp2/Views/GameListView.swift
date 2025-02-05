import SwiftUI
import CoreData

// MARK: - Main View
struct GameListView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    
    // MARK: - Fetch Requests
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Game.startDate, ascending: false)
        ],
        animation: .default)
    private var games: FetchedResults<Game>
    
    // MARK: - State
    @State private var isErrorPresented = false
    @State private var error: Error?
    @State private var gameToDelete: Game?
    @State private var showingDeleteConfirmation = false
    @State private var isLoading = false
    
    // MARK: - Helper Methods
    private func getWinnerForGame(_ game: Game) -> Player? {
        // Get all completed non-skipped rounds
        let completedRounds = game.roundsArray.filter { round in
            round.isCompleted && !round.isSkipped
        }
        
        // Calculate total scores for each player
        var playerScores: [(player: Player, score: Int32)] = []
        
        for player in game.playersArray {
            var totalScore: Int32 = 0
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    totalScore += score
                }
            }
            playerScores.append((player: player, score: totalScore))
        }
        
        // Sort by score (ascending, as lower score is better)
        let sortedScores = playerScores.sorted { $0.score < $1.score }
        return sortedScores.first?.player
    }
    
    // MARK: - View Body
    var body: some View {
        List {
            ForEach(games) { game in
                Button {
                    navigationCoordinator.navigateToGame(game.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            if game.isActive {
                                Text("Round \(game.currentRound)")
                                    .font(.headline)
                            } else {
                                Text("Completed")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                if let endDate = game.endDate {
                                    Text(endDate, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Text(game.playersArray.map { $0.name }.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if !game.isActive {
                            // Show winner using our new calculation method
                            if let winner = getWinnerForGame(game) {
                                VStack(alignment: .trailing) {
                                    Text("Winner")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(winner.name)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if game.isActive {
                        Button(role: .destructive) {
                            deleteGame(game)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text("Start a new game to begin playing")
                )
            }
        }
        .refreshable {
            await refreshGames()
        }
        .alert("Error", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }
    
    // MARK: - Actions
    private func deleteGame(_ game: Game) {
        Task {
            do {
                try await navigationCoordinator.deleteGame(game.id)
                await refreshGames()
            } catch {
                self.error = error
                isErrorPresented = true
            }
        }
    }
    
    private func refreshGames() async {
        isLoading = true
        viewContext.reset()
        try? await Task.sleep(nanoseconds: 100_000_000) // Small delay for UI feedback
        isLoading = false
    }
}

// MARK: - Preview
struct GameListView_Previews: PreviewProvider {
    static var previews: some View {
        let previewContainer = PersistenceController.preview
        let context = previewContainer.container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        let previewContent: AnyView = {
            do {
                // Create a test game for the preview
                let game = try Game.createPreviewGame(in: context)
                
                return AnyView(
                    GameListView()
                        .environment(\.managedObjectContext, context)
                        .environmentObject(DependencyContainer(persistenceController: previewContainer))
                )
            } catch {
                return AnyView(
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                )
            }
        }()
        
        return NavigationStack {
            previewContent
        }
    }
} 