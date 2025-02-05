import SwiftUI
import CoreData

// MARK: - Main View
struct GameSummaryView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var viewModel: GameViewModel
    
    // MARK: - Properties
    let gameID: UUID
    
    init(gameID: UUID) {
        self.gameID = gameID
        let coordinator = GameCoordinator(viewContext: PersistenceController.shared.container.viewContext)
        self._viewModel = StateObject(wrappedValue: GameViewModel.instance(for: gameID, coordinator: coordinator))
    }
    
    // MARK: - Computed Properties
    private var game: Game? {
        viewModel.game
    }
    
    private var lastRound: Round? {
        game?.sortedRounds.last
    }
    
    private var playerScores: [(player: Player, score: Int)] {
        guard let game = game else { return [] }
        
        // Get all completed non-skipped rounds
        let completedRounds = game.roundsArray.filter { round in
            round.isCompleted && !round.isSkipped
        }
        
        // Calculate total scores for each player
        var totalScores: [(player: Player, score: Int)] = []
        
        for player in game.playersArray {
            var total = 0
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    total += Int(score)
                }
            }
            totalScores.append((player: player, score: total))
        }
        
        // Sort by score (ascending, as lower score is better)
        return totalScores.sorted { $0.score < $1.score }
    }
    
    private var winner: Player? {
        playerScores.first?.player
    }
    
    // MARK: - View Body
    var body: some View {
        if let game = game {
            List {
                Section("Final Scores") {
                    ForEach(game.playersArray) { player in
                        HStack {
                            Text(player.name)
                                .font(.headline)
                            Spacer()
                            Text("\(viewModel.getTotalScore(for: player))")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Round Details") {
                    ForEach(game.roundsArray) { round in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Round \(round.number): \(round.description)")
                                .font(.headline)
                            
                            if let scores = round.scores {
                                ForEach(game.playersArray) { player in
                                    if let score = scores[player.id.uuidString] {
                                        HStack {
                                            Text(player.name)
                                                .font(.subheadline)
                                            Spacer()
                                            Text("\(score)")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Game Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        navigationCoordinator.dismissSheet()
                    }
                }
            }
            .task {
                do {
                    if let game = try await viewModel.coordinator.verifyGame(id: gameID) {
                        try await viewModel.loadGame(game)
                    }
                } catch {
                    // Handle error
                }
            }
        } else {
            ContentUnavailableView(
                "Game Not Found",
                systemImage: "exclamationmark.triangle",
                description: Text("The game may have been deleted")
            )
            .onAppear {
                navigationCoordinator.dismissSheet()
            }
        }
    }
}

// MARK: - Preview
struct GameSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = NavigationCoordinator(viewContext: context)
        
        if let game = try? Game.createPreviewGame(in: context) {
            NavigationStack {
                GameSummaryView(gameID: game.id)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(coordinator)
            }
        }
    }
} 