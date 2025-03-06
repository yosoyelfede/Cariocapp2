import SwiftUI
import CoreData

// MARK: - Game History View
struct GameHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var completedGames: [Game] = []
    @State private var selectedGame: Game?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var isErrorAlertPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var gameToDelete: Game?
    @State private var showingDetailView = false
    
    // Grid layout properties
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack {
                if isLoading && completedGames.isEmpty {
                    ProgressView("Loading games...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if completedGames.isEmpty {
                    ContentUnavailableView(
                        "No Completed Games",
                        systemImage: "gamecontroller",
                        description: Text("Completed games will appear here.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Tap a game to view details")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(completedGames) { game in
                                    GameHistoryCard(game: game)
                                        .onTapGesture {
                                            // Show the detail view immediately and preload data
                                            selectedGame = game
                                            showingDetailView = true
                                            
                                            // Preload the game data in the background
                                            preloadGameData(game)
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                gameToDelete = game
                                                isDeleteConfirmationPresented = true
                                            } label: {
                                                Label("Delete Game", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    .refreshable {
                        await loadCompletedGames()
                    }
                }
            }
        }
        .navigationTitle("Game History")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await loadCompletedGames()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .alert("Error", isPresented: $isErrorAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        }
        .confirmationDialog(
            "Delete Game",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let gameToDelete = gameToDelete {
                    Task {
                        await deleteGame(gameToDelete)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this game? This action cannot be undone.")
        }
        .sheet(isPresented: $showingDetailView, onDismiss: {
            // Reset state when sheet is dismissed
            selectedGame = nil
        }) {
            if let selectedGame = selectedGame {
                NavigationStack {
                    GameDetailView(game: selectedGame)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button {
                                    showingDetailView = false
                                } label: {
                                    Text("Done")
                                }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
            }
        }
        .task {
            await loadCompletedGames()
        }
    }
    
    // MARK: - Data Loading
    private func loadCompletedGames() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await fetchCompletedGames()
        } catch {
            self.error = error
            isErrorAlertPresented = true
        }
    }
    
    // MARK: - Game Deletion
    private func deleteGame(_ game: Game) async {
        do {
            // Create a child context for deletion
            let childContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            childContext.parent = viewContext
            
            // Get the game in the child context
            let gameID = game.objectID
            guard let gameInChildContext = childContext.object(with: gameID) as? Game else {
                throw NSError(domain: "GameHistoryView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to find game in context"])
            }
            
            // Delete all rounds
            for round in gameInChildContext.roundsArray {
                childContext.delete(round)
            }
            
            // Clear player snapshots
            if let snapshots = gameInChildContext.playerSnapshots {
                for case let snapshot as NSManagedObject in snapshots {
                    childContext.delete(snapshot)
                }
            }
            
            // Update player relationships
            for player in gameInChildContext.playersArray {
                if var playerGames = player.games as? Set<Game> {
                    playerGames.remove(gameInChildContext)
                    player.games = playerGames as NSSet
                }
            }
            
            // Delete the game
            childContext.delete(gameInChildContext)
            
            // Save the child context
            try childContext.save()
            
            // Save the parent context
            try viewContext.save()
            
            // Update player statistics
            for player in game.playersArray {
                try await updatePlayerStatistics(player)
            }
            
            // Refresh the list
            try await fetchCompletedGames()
        } catch {
            self.error = error
            isErrorAlertPresented = true
        }
    }
    
    // MARK: - Helper Methods
    private func fetchCompletedGames() async throws {
        let fetchRequest: NSFetchRequest<Game> = Game.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isActive == NO")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Game.endDate, ascending: false)]
        
        let games = try viewContext.fetch(fetchRequest)
        
        // Update on main thread
        await MainActor.run {
            self.completedGames = games
        }
    }
    
    // Preload game data in the background
    private func preloadGameData(_ game: Game) {
        // Load all relationships in the background
        DispatchQueue.global(qos: .userInitiated).async {
            // Force loading of all relationships
            let _ = game.roundsArray
            let _ = game.playersArray
            
            // Access player snapshots to ensure they're loaded
            if let snapshots = game.playerSnapshots {
                for case let snapshot as NSManagedObject in snapshots {
                    let _ = snapshot.objectID
                }
            }
            
            // Access round scores to ensure they're loaded
            for round in game.roundsArray {
                let _ = round.scores
            }
        }
    }
    
    private func updatePlayerStatistics(_ player: Player) async throws {
        // Implementation remains the same
        // This is a placeholder for the actual implementation
    }
}

// MARK: - Game History Card
private struct GameHistoryCard: View {
    let game: Game
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                
                Text(game.endDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Winner
            if let winner = game.playerSnapshotsArray.sorted(by: { $0.position < $1.position }).first {
                HStack {
                    Image(systemName: "trophy")
                        .foregroundColor(.yellow)
                    
                    Text(winner.name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            
            // Player count
            HStack {
                Image(systemName: "person.2")
                Text("\(game.playersArray.count) players")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Round count
            HStack {
                Image(systemName: "list.number")
                Text("\(game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }.count) rounds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
}

// MARK: - Game Detail View
private struct GameDetailView: View {
    let game: Game
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Game summary card
                summaryCard
                
                // Final standings card
                standingsCard
                
                // Round details card
                roundDetailsCard
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Game Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with compact layout
            HStack {
                Label {
                    Text("Game Summary")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "gamecontroller")
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(game.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Game info in a more compact layout
            HStack(spacing: 16) {
                // Players
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("Players")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "person.2")
                            .foregroundColor(.blue)
                    }
                    
                    Text(game.playersArray.map { $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
                // Rounds
                VStack(alignment: .center, spacing: 2) {
                    Label {
                        Text("Rounds")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "list.number")
                            .foregroundColor(.blue)
                    }
                    
                    Text("\(game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 8)
                
                // Card color statistics
                let colorStats = game.cardColorStats
                HStack(spacing: 8) {
                    // Red cards
                    VStack(alignment: .center, spacing: 2) {
                        Label {
                            Text("Red")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "suit.diamond")
                                .foregroundColor(.red)
                        }
                        
                        Text(String(format: "%.0f%%", colorStats.redPercentage))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Black cards
                    VStack(alignment: .center, spacing: 2) {
                        Label {
                            Text("Black")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "suit.spade")
                                .foregroundColor(.black)
                        }
                        
                        Text(String(format: "%.0f%%", colorStats.blackPercentage))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Standings Card
    private var standingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            Label {
                Text("Final Standings")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "trophy")
                    .foregroundColor(.yellow)
            }
            
            Divider()
            
            // Player standings in a grid layout
            let snapshots = game.playerSnapshotsArray.sorted { $0.position < $1.position }
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(snapshots, id: \.id) { snapshot in
                    HStack(spacing: 4) {
                        // Position
                        ZStack {
                            Circle()
                                .fill(positionColor(for: snapshot.position))
                                .frame(width: 22, height: 22)
                            
                            Text("\(snapshot.position)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        // Player name
                        Text(snapshot.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        // Score
                        Text("\(snapshot.score)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Round Details Card
    private var roundDetailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            Label {
                Text("Round Details")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "list.number")
                    .foregroundColor(.blue)
            }
            
            Divider()
            
            // Round list in a compact grid layout
            let playedRounds = game.sortedRounds.filter { $0.isCompleted && !$0.isSkipped }
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(playedRounds, id: \.id) { round in
                    CompactRoundDetailView(round: round)
                }
            }
        }
        .padding(10)
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

// MARK: - Compact Round Detail View
private struct CompactRoundDetailView: View {
    let round: Round
    @State private var showDetails = false
    
    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(round.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if let firstCardColor = round.firstCardColor {
                        Circle()
                            .fill(firstCardColor == "red" ? Color.red : Color.black)
                            .frame(width: 10, height: 10)
                    }
                }
                
                if let topScore = round.sortedScores.first {
                    HStack {
                        Text(topScore.player.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(topScore.score)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showDetails) {
            RoundDetailPopover(round: round)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Round Detail Popover
private struct RoundDetailPopover: View {
    let round: Round
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(round.name)
                    .font(.headline)
                
                Spacer()
                
                if let firstCardColor = round.firstCardColor {
                    Label(
                        firstCardColor.capitalized,
                        systemImage: firstCardColor == "red" ? "suit.diamond" : "suit.spade"
                    )
                    .font(.subheadline)
                    .foregroundColor(firstCardColor == "red" ? .red : .primary)
                }
            }
            .padding(.bottom, 4)
            
            Divider()
            
            ForEach(round.sortedScores, id: \.player.id) { scoreEntry in
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
        .padding()
        .frame(width: 250)
    }
}

#Preview {
    GameHistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 