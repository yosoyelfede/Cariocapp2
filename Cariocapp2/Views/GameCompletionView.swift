import SwiftUI
import CoreData

// MARK: - StatBox View
struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .bold()
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - StatisticRow View
struct StatisticRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Game Results View
struct GameResultsView: View {
    let game: Game
    
    private var completedRounds: [Round] {
        game.roundsArray.filter { round in
            round.isCompleted && !round.isSkipped
        }
    }
    
    private var playerScores: [(player: Player, score: Int32)] {
        var totalScores: [(player: Player, score: Int32)] = []
        
        // Get all completed rounds
        let completedRounds = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }
        print("📊 Calculating scores for \(game.roundsArray.count) total rounds")
        print("📊 Found \(completedRounds.count) completed rounds")
        
        // Calculate total scores for each player
        for player in game.playersArray {
            print("📊 Calculating total for \(player.name):")
            var total: Int32 = 0
            
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    total += score  // No conversion needed
                    print("  - Round \(round.number): \(score) points")
                } else {
                    print("  - Round \(round.number): No score found for player \(player.name)")
                }
            }
            
            print("📊 Final total for \(player.name): \(total) points")
            totalScores.append((player: player, score: total))
        }
        
        // Sort by score (ascending)
        return totalScores.sorted { $0.score < $1.score }
    }
    
    private var winner: Player? {
        playerScores.first?.player
    }
    
    var body: some View {
        VStack(spacing: 24) {
            if let winner = winner {
                winnerSection(winner)
            }
            
            statsSection
            
            scoresSection
        }
    }
    
    private func winnerSection(_ winner: Player) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            
            Text("Congratulations")
                .font(.title2)
                .bold()
            
            Text(winner.name)
                .font(.title3)
                .foregroundStyle(.blue)
            
            Text("Winner!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    private var scoresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final Scores")
                .font(.headline)
            
            ForEach(playerScores, id: \.player.id) { score in
                HStack {
                    Text(score.player.name)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(score.score) points")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
    
    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatBox(
                    title: "Rounds",
                    value: "\(completedRounds.count)",
                    icon: "number.circle.fill",
                    color: .blue
                )
                
                StatBox(
                    title: "Duration",
                    value: formatDuration(startDate: game.startDate),
                    icon: "clock.fill",
                    color: .orange
                )
            }
            
            HStack(spacing: 12) {
                StatBox(
                    title: "Red Cards",
                    value: String(format: "%.1f%%", game.cardColorStats.redPercentage),
                    icon: "circle.fill",
                    color: .red
                )
                
                StatBox(
                    title: "Black Cards",
                    value: String(format: "%.1f%%", game.cardColorStats.blackPercentage),
                    icon: "circle.fill",
                    color: .primary
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
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
}

// MARK: - Main View
struct GameCompletionView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    
    // MARK: - Properties
    let gameID: UUID
    
    // MARK: - State
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isCompleting = false
    
    // MARK: - Game Completion Logic
    private func completeGame() async throws {
        guard !isCompleting else { return }
        isCompleting = true
        
        do {
            try await navigationCoordinator.completeGame(gameID)
        } catch {
            print("❌ Error completing game: \(error)")
            errorMessage = error.localizedDescription
            showingError = true
        }
        
        isCompleting = false
    }
    
    // MARK: - View Body
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Game Complete!")
                    .font(.largeTitle)
                    .bold()
                
                if let game = navigationCoordinator.getGame(id: gameID) {
                    GameResultsView(game: game)
                }
                
                actionButtons
            }
            .padding()
        }
    }
    
    private var actionButtons: some View {
        Button {
            Task {
                try? await completeGame()
            }
        } label: {
            Text("Return to Main Menu")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
        }
        .disabled(isCompleting)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Preview
struct GameCompletionView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = NavigationCoordinator(viewContext: context)
        
        if let game = try? Game.createPreviewGame(in: context) {
            NavigationStack {
                GameCompletionView(gameID: game.id)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(coordinator)
            }
        }
    }
} 