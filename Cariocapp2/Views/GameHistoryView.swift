import SwiftUI
import CoreData

// MARK: - Game History View
struct GameHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var repository: GameRepository
    @State private var games: [Game] = []
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init() {
        let repository = GameRepository(context: PersistenceController.shared.container.viewContext)
        self._repository = StateObject(wrappedValue: repository)
    }
    
    var body: some View {
        List {
            if games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text("Play some games to see your history")
                )
            } else {
                ForEach(games) { game in
                    GameHistoryRowView(game: game)
                }
            }
        }
        .navigationTitle("Game History")
        .onAppear {
            repository.updateContext(viewContext)
            refreshGames()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func refreshGames() {
        do {
            // Fetch all completed games, sorted by date
            games = try repository.getAllGames().filter { !$0.isActive }
                .sorted { $0.startDate > $1.startDate }
        } catch {
            errorMessage = "Failed to load games"
            showingError = true
        }
    }
}

// MARK: - Game History Row View
private struct GameHistoryRowView: View {
    let game: Game
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Date and Round Count
            HStack {
                Label {
                    Text(game.startDate.formatted(date: .abbreviated, time: .shortened))
                } icon: {
                    Image(systemName: "calendar")
                }
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Label {
                    Text("\(getCompletedRoundCount(game)) rounds")
                } icon: {
                    Image(systemName: "number.circle.fill")
                }
                .foregroundStyle(.secondary)
            }
            .font(.footnote)
            
            // Players and Scores
            VStack(alignment: .leading, spacing: 8) {
                // Players list
                Text(playerList)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Card Statistics
                HStack(spacing: 16) {
                    Label {
                        Text(String(format: "%.0f%%", game.cardColorStats.redPercentage))
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                    }
                    .font(.subheadline)
                    
                    Label {
                        Text(String(format: "%.0f%%", game.cardColorStats.blackPercentage))
                    } icon: {
                        Image(systemName: "circle.fill")
                    }
                    .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                
                // Final Scores
                let scores = calculateFinalScores(for: game)
                HStack(spacing: 12) {
                    ForEach(Array(scores.enumerated()), id: \.element.player.id) { index, score in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playerName(score.player))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("\(score.score) pts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if index < scores.count - 1 {
                            Divider()
                                .frame(height: 24)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .containerRelativeFrame(.horizontal) { width, axis in
            width * 0.95
        }
    }
    
    private var playerList: String {
        game.playersArray.map { playerName($0) }.joined(separator: ", ")
    }
    
    private func playerName(_ player: Player) -> String {
        if player.isGuest {
            // Use shorter format if we have many players
            return game.playersArray.count > 3 ? 
                "\(player.name) (g)" : 
                "\(player.name) (guest)"
        }
        return player.name
    }
    
    private func getCompletedRoundCount(_ game: Game) -> Int {
        game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }.count
    }
    
    private struct PlayerScore: Identifiable {
        let player: Player
        let score: Int32
        var id: UUID { player.id }
    }
    
    private func calculateFinalScores(for game: Game) -> [PlayerScore] {
        // Get all completed non-skipped rounds
        let completedRounds = game.roundsArray.filter { round in
            round.isCompleted && !round.isSkipped
        }
        
        // Calculate total scores for each player
        var playerScores: [PlayerScore] = []
        
        for player in game.playersArray {
            var totalScore: Int32 = 0
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    totalScore += score
                }
            }
            playerScores.append(PlayerScore(player: player, score: totalScore))
        }
        
        // Sort by score (ascending, as lower score is better)
        return playerScores.sorted { $0.score < $1.score }
    }
}

#Preview {
    NavigationStack {
        GameHistoryView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
} 