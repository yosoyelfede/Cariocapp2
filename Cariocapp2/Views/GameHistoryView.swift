import SwiftUI
import CoreData

// MARK: - Game History View
struct GameHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Game.endDate, ascending: false)],
        predicate: NSPredicate(format: "endDate != nil"),
        animation: .default
    ) private var games: FetchedResults<Game>
    
    var body: some View {
        NavigationView {
            List {
                if games.isEmpty {
                    ContentUnavailableView(
                        "No Completed Games",
                        systemImage: "gamecontroller",
                        description: Text("Complete a game to see it here")
                    )
                } else {
                    ForEach(games) { game in
                        GameHistoryRowView(game: game)
                    }
                }
            }
            .navigationTitle("Game History")
            .refreshable {
                viewContext.refreshAllObjects()
                
                // Debug information
                print("🔍 Refreshing Game History")
                let request = NSFetchRequest<Game>(entityName: "Game")
                request.predicate = NSPredicate(format: "endDate != nil")
                
                if let allGames = try? viewContext.fetch(request) {
                    print("🔍 Found \(allGames.count) completed games")
                    for game in allGames {
                        print("🔍 Game: \(game.id), endDate: \(String(describing: game.endDate)), isActive: \(game.isActive), players: \(game.playersArray.map { $0.name })")
                    }
                }
                
                // Fix any games that might be incorrectly marked
                fixGameStates()
            }
            .onAppear {
                viewContext.refreshAllObjects()
                
                // Debug information
                print("🔍 Game History View Appeared")
                let request = NSFetchRequest<Game>(entityName: "Game")
                
                if let allGames = try? viewContext.fetch(request) {
                    print("🔍 Found \(allGames.count) total games")
                    let activeGames = allGames.filter { $0.isActive }
                    let inactiveGames = allGames.filter { !$0.isActive }
                    print("🔍 Active games: \(activeGames.count), Inactive games: \(inactiveGames.count)")
                }
                
                // Fix any games that might be incorrectly marked
                fixGameStates()
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
                    
                    // Update player statistics
                    for player in game.playersArray {
                        print("🔧 Updating statistics for player \(player.name)")
                        player.updateStatistics()
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

private struct GameHistoryRowView: View {
    let game: Game
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(game.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(game.roundsArray.count) rounds")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            let snapshots = game.playerSnapshotsArray
            if !snapshots.isEmpty {
                ForEach(snapshots.sorted { $0.position < $1.position }, id: \.id) { snapshot in
                    HStack {
                        Text("\(snapshot.position). \(snapshot.name)")
                        Spacer()
                        Text("\(snapshot.score)")
                    }
                }
            } else {
                Text("No player data available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GameHistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 