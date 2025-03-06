import SwiftUI
import CoreData

// MARK: - Game History View
struct GameHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var completedGames: [Game] = []
    @State private var selectedGame: Game?
    @State private var isLoading = true
    
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ZStack {
                List(completedGames, selection: $selectedGame) { game in
                    GameHistoryListRow(game: game)
                        .tag(game)
                }
                .overlay {
                    if completedGames.isEmpty && !isLoading {
                        ContentUnavailableView(
                            "No Completed Games",
                            systemImage: "gamecontroller",
                            description: Text("Complete a game to see it here")
                        )
                    }
                }
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Game History")
            .refreshable {
                await loadCompletedGames()
            }
        } detail: {
            if let game = selectedGame {
                GameDetailView(game: game)
            } else {
                ContentUnavailableView(
                    "No Game Selected",
                    systemImage: "gamecontroller",
                    description: Text("Select a game to view details")
                )
            }
        }
        .onAppear {
            Task {
                await loadCompletedGames()
            }
        }
    }
    
    private func loadCompletedGames() async {
        isLoading = true
        
        // Run on background thread
        await Task.yield()
        
        // Fix any games that might be incorrectly marked
        fixGameStates()
        
        // Fetch completed games
        let request = NSFetchRequest<Game>(entityName: "Game")
        request.predicate = NSPredicate(format: "isActive == NO AND endDate != nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Game.endDate, ascending: false)]
        
        do {
            let games = try viewContext.fetch(request)
            print("🔍 Found \(games.count) completed games")
            
            // Debug information
            for game in games {
                print("🔍 Game: \(game.id), endDate: \(String(describing: game.endDate)), isActive: \(game.isActive), players: \(game.playersArray.map { $0.name })")
                print("🔍 Game snapshots: \(game.playerSnapshotsArray.count)")
                
                // Create snapshots if missing
                if game.playerSnapshotsArray.isEmpty {
                    print("🔍 Creating missing snapshots for game \(game.id)")
                    game.createSnapshot()
                    try viewContext.save()
                }
            }
            
            // Update UI on main thread
            await MainActor.run {
                self.completedGames = games
                self.isLoading = false
                
                // Select the first game if available and none is selected
                if self.selectedGame == nil && !games.isEmpty {
                    self.selectedGame = games.first
                }
            }
        } catch {
            print("❌ Error fetching completed games: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func fixGameStates() {
        let request = NSFetchRequest<Game>(entityName: "Game")
        
        if let allGames = try? viewContext.fetch(request) {
            var needsSave = false
            
            for game in allGames {
                // Fix games that are complete but still marked as active
                if game.isActive && game.isComplete {
                    print("🔧 Fixing game \(game.id) - complete but marked active")
                    game.isActive = false
                    game.endDate = game.endDate ?? Date()
                    
                    // Create player snapshots if missing
                    if game.playerSnapshotsArray.isEmpty {
                        print("🔧 Creating missing player snapshots for game \(game.id)")
                        game.createSnapshot()
                    }
                    
                    needsSave = true
                }
                
                // Fix games that have no end date but are inactive
                if !game.isActive && game.endDate == nil {
                    print("🔧 Fixing game \(game.id) - inactive but no end date")
                    game.endDate = Date()
                    needsSave = true
                }
                
                // Fix games that have player snapshots but they're empty or incorrect
                if !game.isActive && game.endDate != nil && (game.playerSnapshotsArray.isEmpty || game.playerSnapshotsArray.first?.position == 0) {
                    print("🔧 Fixing missing or incorrect player snapshots for game \(game.id)")
                    game.createSnapshot()
                    needsSave = true
                }
            }
            
            if needsSave {
                do {
                    try viewContext.save()
                    print("🔧 Saved fixes to game states")
                    
                    // Refresh the view context after saving
                    viewContext.refreshAllObjects()
                    
                    // Update all player statistics
                    updateAllPlayerStatistics()
                } catch {
                    print("❌ Error saving game state fixes: \(error)")
                }
            }
        }
    }
    
    private func updateAllPlayerStatistics() {
        let request = NSFetchRequest<Player>(entityName: "Player")
        
        if let allPlayers = try? viewContext.fetch(request) {
            print("🔧 Updating statistics for \(allPlayers.count) players")
            
            for player in allPlayers {
                player.updateStatistics()
            }
            
            do {
                try viewContext.save()
                print("🔧 Saved updated player statistics")
            } catch {
                print("❌ Error saving player statistics: \(error)")
            }
        }
    }
}

// MARK: - Game History List Row
private struct GameHistoryListRow: View {
    let game: Game
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Date
            Text(game.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")
                .font(.headline)
            
            // Players
            Text(game.playersArray.map { $0.name }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Game Detail View
private struct GameDetailView: View {
    let game: Game
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Game summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("Game Summary")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Date:")
                                .fontWeight(.medium)
                            Text(game.endDate?.formatted(date: .long, time: .shortened) ?? "Unknown")
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Rounds:")
                                .fontWeight(.medium)
                            Text("\(game.roundsArray.count)")
                        }
                    }
                    
                    // Card color statistics
                    let colorStats = game.cardColorStats
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Red cards:")
                                .fontWeight(.medium)
                            Text(String(format: "%.1f%%", colorStats.redPercentage))
                                .foregroundColor(.red)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Black cards:")
                                .fontWeight(.medium)
                            Text(String(format: "%.1f%%", colorStats.blackPercentage))
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                
                // Final standings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Final Standings")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    let snapshots = game.playerSnapshotsArray.sorted { $0.position < $1.position }
                    ForEach(snapshots, id: \.id) { snapshot in
                        HStack {
                            Text("\(snapshot.position).")
                                .fontWeight(.bold)
                            Text(snapshot.name)
                            Spacer()
                            Text("\(snapshot.score)")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                
                // Round details
                VStack(alignment: .leading, spacing: 8) {
                    Text("Round Details")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    ForEach(game.sortedRounds, id: \.id) { round in
                        RoundDetailRow(round: round)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("Game Details")
    }
}

// MARK: - Round Detail Row
private struct RoundDetailRow: View {
    let round: Round
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Round \(round.number)")
                    .font(.headline)
                
                Spacer()
                
                if let firstCardColor = round.firstCardColor {
                    Text("First card: \(firstCardColor)")
                        .font(.subheadline)
                        .foregroundColor(firstCardColor == "red" ? .red : .primary)
                }
            }
            
            Divider()
            
            // Player scores for this round
            let sortedScores = round.sortedScores
            ForEach(sortedScores, id: \.player.id) { scoreEntry in
                HStack {
                    Text(scoreEntry.player.name)
                    Spacer()
                    Text("\(scoreEntry.score)")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    GameHistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 