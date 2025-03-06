import SwiftUI
import CoreData
import os

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
    @State private var dataIsPreloaded = false
    
    // Grid layout properties
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        GameHistoryContent(
            isLoading: isLoading,
            completedGames: completedGames,
            selectedGame: $selectedGame,
            showingDetailView: $showingDetailView,
            dataIsPreloaded: $dataIsPreloaded,
            error: $error,
            isErrorAlertPresented: $isErrorAlertPresented,
            preloadGameDataAsync: preloadGameDataAsync,
            loadCompletedGames: loadCompletedGames,
            gameToDelete: $gameToDelete,
            isDeleteConfirmationPresented: $isDeleteConfirmationPresented
        )
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
            Logger.logUIEvent("Detail view dismissed, resetting state")
            selectedGame = nil
            dataIsPreloaded = false
        }) {
            if let selectedGame = selectedGame {
                NavigationStack {
                    GameDetailView(game: selectedGame, dataIsPreloaded: dataIsPreloaded)
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
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
            }
        }
        .task {
            await loadCompletedGames()
        }
    }
    
    // Extract the content into a separate view to reduce complexity
    private struct GameHistoryContent: View {
        let isLoading: Bool
        let completedGames: [Game]
        @Binding var selectedGame: Game?
        @Binding var showingDetailView: Bool
        @Binding var dataIsPreloaded: Bool
        @Binding var error: Error?
        @Binding var isErrorAlertPresented: Bool
        let preloadGameDataAsync: (Game) async -> Void
        var loadCompletedGames: () async -> Void
        var gameToDelete: Binding<Game?>
        var isDeleteConfirmationPresented: Binding<Bool>
        
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
                        GameHistoryList(
                            completedGames: completedGames,
                            selectedGame: $selectedGame,
                            showingDetailView: $showingDetailView,
                            dataIsPreloaded: $dataIsPreloaded,
                            preloadGameDataAsync: preloadGameDataAsync,
                            loadCompletedGames: loadCompletedGames,
                            gameToDelete: gameToDelete,
                            isDeleteConfirmationPresented: isDeleteConfirmationPresented
                        )
                    }
                }
                .navigationTitle("Game History")
                .alert(isPresented: $isErrorAlertPresented) {
                    Alert(
                        title: Text("Error"),
                        message: Text(error?.localizedDescription ?? "An unknown error occurred"),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }
    
    // Extract the game list into a separate view
    private struct GameHistoryList: View {
        let completedGames: [Game]
        @Binding var selectedGame: Game?
        @Binding var showingDetailView: Bool
        @Binding var dataIsPreloaded: Bool
        let preloadGameDataAsync: (Game) async -> Void
        var loadCompletedGames: () async -> Void
        var gameToDelete: Binding<Game?>
        var isDeleteConfirmationPresented: Binding<Bool>
        
        private let columns: [GridItem] = [
            GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
        ]
        
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Completed Games")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(completedGames) { game in
                            GameHistoryCard(game: game)
                                .onTapGesture {
                                    Logger.logUIEvent("Game card tapped: \(game.id.uuidString)")
                                    selectedGame = game
                                    dataIsPreloaded = false
                                    showingDetailView = true
                                    
                                    // Preload data asynchronously
                                    Task {
                                        await preloadGameDataAsync(game)
                                        dataIsPreloaded = true
                                        Logger.logUIEvent("Data preloading completed for game: \(game.id.uuidString)")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        gameToDelete.wrappedValue = game
                                        isDeleteConfirmationPresented.wrappedValue = true
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
    
    // MARK: - Data Loading
    private func loadCompletedGames() async {
        Logger.logUIEvent("Loading completed games")
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await fetchCompletedGames()
            Logger.logUIEvent("Successfully loaded \(completedGames.count) completed games")
        } catch {
            Logger.logError(error, category: Logger.ui)
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
    
    // Preload game data asynchronously
    private func preloadGameDataAsync(_ game: Game) async {
        Logger.logUIEvent("Starting async preload for game: \(game.id.uuidString)")
        
        // Perform on a background thread to avoid UI blocking
        await Task.detached(priority: .userInitiated) {
            // Force loading of all relationships
            Logger.logUIEvent("Loading rounds array")
            let rounds = game.roundsArray
            Logger.logUIEvent("Loaded \(rounds.count) rounds")
            
            Logger.logUIEvent("Loading players array")
            let players = game.playersArray
            Logger.logUIEvent("Loaded \(players.count) players")
            
            // Access player snapshots to ensure they're loaded
            Logger.logUIEvent("Loading player snapshots")
            if let snapshots = game.playerSnapshots {
                var count = 0
                for case let snapshot as NSManagedObject in snapshots {
                    let _ = snapshot.objectID
                    count += 1
                }
                Logger.logUIEvent("Loaded \(count) player snapshots")
            }
            
            // Access round scores to ensure they're loaded
            Logger.logUIEvent("Loading round scores")
            for round in rounds {
                let _ = round.scores
                let _ = round.firstCardColor
                
                // Force loading of player relationships in scores
                if let scores = round.scores as? Set<NSManagedObject> {
                    for case let score as NSManagedObject in scores {
                        let _ = score.objectID
                    }
                }
            }
            
            // Force loading of card color stats
            Logger.logUIEvent("Loading card color stats")
            let colorStats = game.cardColorStats
            Logger.logUIEvent("Card color stats - Red: \(colorStats.redPercentage)%, Black: \(colorStats.blackPercentage)%")
            
            Logger.logUIEvent("Preloading completed for game: \(game.id.uuidString)")
        }.value
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
    let dataIsPreloaded: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isDataLoaded = false
    
    var body: some View {
        ZStack {
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
                .opacity(isDataLoaded ? 1 : 0)
            }
            
            if !isDataLoaded {
                ProgressView("Loading game details...")
            }
        }
        .navigationTitle("Game Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            Logger.logUIEvent("GameDetailView appeared for game: \(game.id.uuidString), dataIsPreloaded: \(dataIsPreloaded)")
            if dataIsPreloaded {
                // If data is already preloaded, just mark as loaded
                Logger.logUIEvent("Data was preloaded, marking as loaded")
                isDataLoaded = true
            } else {
                // Otherwise load it now
                Logger.logUIEvent("Data was not preloaded, loading now")
                Task {
                    await loadGameData()
                }
            }
        }
    }
    
    // Load game data asynchronously
    private func loadGameData() async {
        Logger.logUIEvent("Starting to load game data for game: \(game.id.uuidString)")
        
        // Force loading of all relationships if not already loaded
        Logger.logUIEvent("Loading rounds array")
        let rounds = game.roundsArray
        Logger.logUIEvent("Loaded \(rounds.count) rounds")
        
        Logger.logUIEvent("Loading players array")
        let players = game.playersArray
        Logger.logUIEvent("Loaded \(players.count) players")
        
        Logger.logUIEvent("Loading player snapshots")
        let snapshots = game.playerSnapshotsArray
        Logger.logUIEvent("Loaded \(snapshots.count) player snapshots")
        
        Logger.logUIEvent("Loading card color stats")
        let colorStats = game.cardColorStats
        Logger.logUIEvent("Card color stats - Red: \(colorStats.redPercentage)%, Black: \(colorStats.blackPercentage)%")
        
        // Access round scores to ensure they're loaded
        Logger.logUIEvent("Loading round scores")
        for round in rounds {
            let _ = round.scores
            let _ = round.firstCardColor
            
            // Force loading of player relationships in scores
            if let scores = round.scores as? Set<NSManagedObject> {
                for case let score as NSManagedObject in scores {
                    let _ = score.objectID
                }
            }
        }
        
        // Mark data as loaded on the main thread
        await MainActor.run {
            Logger.logUIEvent("Data loading completed, updating UI")
            isDataLoaded = true
        }
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