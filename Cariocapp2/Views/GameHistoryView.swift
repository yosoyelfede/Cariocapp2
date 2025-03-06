import SwiftUI
import CoreData

// MARK: - Game History View
struct GameHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var completedGames: [Game] = []
    @State private var selectedGame: Game?
    @State private var isLoading = true
    @State private var gameToDelete: Game?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar (Game List)
            ZStack {
                List(completedGames, selection: $selectedGame) { game in
                    GameHistoryListRow(game: game)
                        .tag(game)
                        .contextMenu {
                            Button(role: .destructive) {
                                gameToDelete = game
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onLongPressGesture {
                            gameToDelete = game
                            showingDeleteConfirmation = true
                        }
                }
                .listStyle(SidebarListStyle())
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
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
            .alert("Delete Game", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    gameToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let game = gameToDelete {
                        deleteGame(game)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this game? This action cannot be undone.")
            }
        } detail: {
            // Detail View
            if let game = selectedGame {
                GameDetailView(game: game)
                    .id(game.id) // Force refresh when selection changes
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
                } catch {
                    print("❌ Error saving game state fixes: \(error)")
                }
            }
        }
    }
    
    // This method is now only called explicitly when needed
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
    
    // Add a method to delete games
    private func deleteGame(_ game: Game) {
        Task {
            do {
                print("🗑️ Deleting game: \(game.id)")
                
                // If this is the selected game, deselect it
                if selectedGame?.id == game.id {
                    selectedGame = nil
                }
                
                // Delete the game
                viewContext.delete(game)
                
                // Save changes
                try viewContext.save()
                
                // Refresh the list
                await loadCompletedGames()
                
                print("🗑️ Game deleted successfully")
            } catch {
                print("❌ Error deleting game: \(error)")
            }
        }
    }
}

// MARK: - Game History List Row
private struct GameHistoryListRow: View {
    let game: Game
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text(game.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")
                    .font(.headline)
            }
            
            // Players
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "person.2")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                Text(game.playersArray.map { $0.name }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Game Detail View
private struct GameDetailView: View {
    let game: Game
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Game summary card
                summaryCard
                
                // Final standings card
                standingsCard
                
                // Round details card
                roundDetailsCard
            }
            .padding()
            .frame(maxWidth: 800, alignment: .center) // Limit width for better readability on large screens
        }
        .navigationTitle("Game Details")
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Game Summary", systemImage: "gamecontroller")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text(game.endDate?.formatted(date: .long, time: .shortened) ?? "Unknown")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Game info
            HStack(spacing: 20) {
                // Players
                VStack(alignment: .leading, spacing: 4) {
                    Label("Players", systemImage: "person.2")
                        .font(.headline)
                    
                    Text(game.playersArray.map { $0.name }.joined(separator: ", "))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Rounds
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Rounds", systemImage: "list.number")
                        .font(.headline)
                    
                    Text("\(game.roundsArray.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Card color statistics
            let colorStats = game.cardColorStats
            HStack(spacing: 20) {
                // Red cards
                VStack(alignment: .leading, spacing: 4) {
                    Label("Red Cards", systemImage: "suit.diamond")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(String(format: "%.1f%%", colorStats.redPercentage))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Black cards
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Black Cards", systemImage: "suit.spade")
                        .font(.headline)
                    
                    Text(String(format: "%.1f%%", colorStats.blackPercentage))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Standings Card
    private var standingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Final Standings", systemImage: "trophy")
                .font(.title2)
                .fontWeight(.bold)
            
            Divider()
            
            // Player standings
            let snapshots = game.playerSnapshotsArray.sorted { $0.position < $1.position }
            ForEach(snapshots, id: \.id) { snapshot in
                HStack {
                    // Position
                    ZStack {
                        Circle()
                            .fill(positionColor(for: snapshot.position))
                            .frame(width: 28, height: 28)
                        
                        Text("\(snapshot.position)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    // Player name
                    Text(snapshot.name)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Score
                    Text("\(snapshot.score)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                
                if snapshot.position < snapshots.count {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Round Details Card
    private var roundDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Round Details", systemImage: "list.number")
                .font(.title2)
                .fontWeight(.bold)
            
            Divider()
            
            // Round list
            ForEach(game.sortedRounds, id: \.id) { round in
                RoundDetailRow(round: round)
                
                if round.number < game.sortedRounds.count {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // Helper function for position colors
    private func positionColor(for position: Int) -> Color {
        switch position {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .blue
        }
    }
}

// MARK: - Round Detail Row
private struct RoundDetailRow: View {
    let round: Round
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Round header (always visible)
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("Round \(round.number)")
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundColor(.secondary)
                        .animation(.easeInOut, value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Player scores (expandable)
            if isExpanded {
                VStack(spacing: 8) {
                    // First card info
                    if let firstCardColor = round.firstCardColor {
                        HStack {
                            Label("First card:", systemImage: "suit.club")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(firstCardColor)
                                .font(.subheadline)
                                .foregroundColor(firstCardColor == "red" ? .red : .primary)
                            
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    
                    Divider()
                    
                    // Player scores
                    let sortedScores = round.sortedScores
                    ForEach(sortedScores, id: \.player.id) { scoreEntry in
                        HStack {
                            Text(scoreEntry.player.name)
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Text("\(scoreEntry.score)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.leading, 8)
                .transition(.opacity)
                .animation(.easeInOut, value: isExpanded)
            }
        }
    }
}

#Preview {
    GameHistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 