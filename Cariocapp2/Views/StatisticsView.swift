import SwiftUI
import CoreData

struct StatisticsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Game.startDate, ascending: false)
        ],
        predicate: NSPredicate(format: "isActive == false AND currentRound >= maxRounds"),
        animation: .default)
    private var completedGames: FetchedResults<Game>
    
    var body: some View {
        List {
            if completedGames.isEmpty {
                ContentUnavailableView(
                    "No Completed Games",
                    systemImage: "clock",
                    description: Text("Complete some games to see them here")
                )
            } else {
                ForEach(completedGames) { game in
                    GameHistoryRow(game: game)
                }
            }
        }
        .navigationTitle("Game History")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Game History Row
struct GameHistoryRow: View {
    let game: Game
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date and Duration
            HStack {
                Text(game.startDate, style: .date)
                    .font(.headline)
                Spacer()
                Text(formatDuration(startDate: game.startDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Players and Scores
            VStack(alignment: .leading, spacing: 4) {
                ForEach(calculateFinalScores(for: game).sorted(by: { $0.score < $1.score })) { playerScore in
                    HStack {
                        Text(playerScore.player.name)
                        Spacer()
                        Text("\(playerScore.score)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(startDate: Date) -> String {
        let duration = Int(Date().timeIntervalSince(startDate))
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private struct PlayerScoreInfo: Identifiable {
        let id = UUID()
        let player: Player
        let score: Int
    }
    
    private func calculateFinalScores(for game: Game) -> [PlayerScoreInfo] {
        var playerScores: [PlayerScoreInfo] = []
        
        for player in game.playersArray {
            var totalScore = 0
            for round in game.roundsArray {
                totalScore += Int(round.getScore(for: player))
            }
            playerScores.append(PlayerScoreInfo(player: player, score: totalScore))
        }
        
        return playerScores
    }
}

// MARK: - Preview
struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StatisticsView()
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
} 