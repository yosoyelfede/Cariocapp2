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
                                    // Prepare the game data synchronously before showing the detail view
                                    prepareGameDataSynchronously(game)
                                    selectedGame = game
                                    dataIsPreloaded = true
                                    showingDetailView = true
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
        
        // Synchronously prepare game data before showing detail view
        private func prepareGameDataSynchronously(_ game: Game) {
            Logger.logUIEvent("Preparing game data synchronously for game: \(game.id.uuidString)")
            
            // Force immediate loading of all relationships
            _ = game.roundsArray
            _ = game.playersArray
            
            // Access player snapshots to ensure they're loaded
            let snapshots = game.playerSnapshotsArray
            for snapshot in snapshots {
                _ = snapshot.name
                _ = snapshot.position
                _ = snapshot.score
            }
            
            // Access round scores to ensure they're loaded
            for round in game.roundsArray {
                _ = round.name
                _ = round.firstCardColor
                let scores = round.sortedScores
                for score in scores {
                    _ = score.player.name
                    _ = score.score
                }
            }
            
            // Force loading of card color stats
            _ = game.cardColorStats
            
            Logger.logUIEvent("Game data prepared synchronously for game: \(game.id.uuidString)")
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
        // Force immediate loading of all relationships
        _ = game.roundsArray
        _ = game.playersArray
        
        // Access player snapshots to ensure they're loaded
        _ = game.playerSnapshotsArray
        
        // Access round scores to ensure they're loaded
        for round in game.roundsArray {
            _ = round.scores
            _ = round.firstCardColor
        }
        
        // Force loading of card color stats
        _ = game.cardColorStats
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
    @State private var viewModel: GameDetailViewModel
    @State private var isDataLoaded = false
    
    init(game: Game, dataIsPreloaded: Bool) {
        self.game = game
        self.dataIsPreloaded = dataIsPreloaded
        // Initialize the view model with the game data
        _viewModel = State(initialValue: GameDetailViewModel(game: game))
        Logger.logUIEvent("GameDetailView initialized for game: \(game.id.uuidString)")
    }
    
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
        .onAppear {
            Logger.logUIEvent("GameDetailView appeared for game: \(game.id.uuidString)")
            // Force synchronous data loading to ensure all data is available
            forceSynchronousDataLoading()
            // Ensure the view model has loaded all data
            viewModel.loadAllData()
            isDataLoaded = true
            Logger.logUIEvent("GameDetailView data loaded for game: \(game.id.uuidString)")
        }
    }
    
    // Force synchronous loading of all data
    private func forceSynchronousDataLoading() {
        Logger.logUIEvent("Forcing synchronous data loading for game: \(game.id.uuidString)")
        
        // Access all critical properties to force Core Data to load them
        _ = game.endDate
        _ = game.playersArray.map { $0.name }
        
        // Access player snapshots
        let snapshots = game.playerSnapshotsArray
        for snapshot in snapshots {
            _ = snapshot.name
            _ = snapshot.position
            _ = snapshot.score
        }
        
        // Access rounds and scores
        for round in game.roundsArray {
            _ = round.name
            _ = round.firstCardColor
            let scores = round.sortedScores
            for score in scores {
                _ = score.player.name
                _ = score.score
            }
        }
        
        // Access card color stats
        _ = game.cardColorStats
        
        Logger.logUIEvent("Synchronous data loading completed for game: \(game.id.uuidString)")
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
                
                Text(viewModel.formattedEndDate)
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
                    
                    Text(viewModel.playerNames)
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
                    
                    Text("\(viewModel.completedRoundsCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 8)
                
                // Card color statistics
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
                        
                        Text(viewModel.redPercentage)
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
                        
                        Text(viewModel.blackPercentage)
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
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(viewModel.playerSnapshots) { snapshot in
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
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(viewModel.playedRounds) { roundData in
                    CompactRoundDetailView(roundData: roundData)
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

// MARK: - Game Detail View Model
private class GameDetailViewModel: ObservableObject {
    // Game summary data
    let formattedEndDate: String
    let playerNames: String
    let completedRoundsCount: Int
    let redPercentage: String
    let blackPercentage: String
    
    // Player standings data
    struct PlayerSnapshotData: Identifiable {
        let id: UUID
        let name: String
        let position: Int
        let score: Int
    }
    let playerSnapshots: [PlayerSnapshotData]
    
    // Round details data
    struct RoundData: Identifiable {
        let id: UUID
        let name: String
        let firstCardColor: String?
        let topScorePlayerName: String?
        let topScore: Int?
        let scores: [ScoreData]
        
        struct ScoreData: Identifiable {
            let id: UUID
            let playerName: String
            let score: Int
        }
    }
    let playedRounds: [RoundData]
    
    // Initialize with a game
    init(game: Game) {
        Logger.logUIEvent("Initializing GameDetailViewModel for game: \(game.id.uuidString)")
        
        // Initialize with default values
        self.formattedEndDate = game.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"
        self.playerNames = game.playersArray.map { $0.name }.joined(separator: ", ")
        self.completedRoundsCount = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }.count
        
        let colorStats = game.cardColorStats
        self.redPercentage = String(format: "%.0f%%", colorStats.redPercentage)
        self.blackPercentage = String(format: "%.0f%%", colorStats.blackPercentage)
        
        // Extract player snapshots
        self.playerSnapshots = game.playerSnapshotsArray.sorted { $0.position < $1.position }.map { snapshot in
            let snapshotScore = Int(snapshot.score) // Ensure we convert Int32 to Int
            Logger.logUIEvent("Processing player snapshot: \(snapshot.name), score: \(snapshotScore)")
            return PlayerSnapshotData(
                id: snapshot.id,
                name: snapshot.name,
                position: snapshot.position,
                score: snapshotScore
            )
        }
        
        // Extract round data
        self.playedRounds = game.sortedRounds.filter { $0.isCompleted && !$0.isSkipped }.map { round in
            Logger.logUIEvent("Processing round: \(round.name)")
            let scores = round.sortedScores.map { score in
                let scoreValue = Int(score.score) // Ensure we convert Int32 to Int
                Logger.logUIEvent("Processing score for player: \(score.player.name), score: \(scoreValue)")
                return RoundData.ScoreData(
                    id: score.player.id,
                    playerName: score.player.name,
                    score: scoreValue
                )
            }
            
            let topScore = round.sortedScores.first != nil ? Int(round.sortedScores.first!.score) : nil
            
            return RoundData(
                id: round.id,
                name: round.name,
                firstCardColor: round.firstCardColor,
                topScorePlayerName: round.sortedScores.first?.player.name,
                topScore: topScore,
                scores: scores
            )
        }
        
        Logger.logUIEvent("GameDetailViewModel initialization complete for game: \(game.id.uuidString)")
    }
    
    // Force loading of all data
    func loadAllData() {
        Logger.logUIEvent("GameDetailViewModel.loadAllData() called")
        // This method is called to ensure all data is loaded
        // The data is already loaded in the initializer, so this is just a placeholder
    }
}

// MARK: - Compact Round Detail View
private struct CompactRoundDetailView: View {
    let roundData: GameDetailViewModel.RoundData
    @State private var showDetails = false
    
    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(roundData.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if let firstCardColor = roundData.firstCardColor {
                        Circle()
                            .fill(firstCardColor == "red" ? Color.red : Color.black)
                            .frame(width: 10, height: 10)
                    }
                }
                
                if let playerName = roundData.topScorePlayerName, let score = roundData.topScore {
                    HStack {
                        Text(playerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(score)")
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
            RoundDetailPopover(roundData: roundData)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Round Detail Popover
private struct RoundDetailPopover: View {
    let roundData: GameDetailViewModel.RoundData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(roundData.name)
                    .font(.headline)
                
                Spacer()
                
                if let firstCardColor = roundData.firstCardColor {
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
            
            ForEach(roundData.scores) { scoreData in
                HStack {
                    Text(scoreData.playerName)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text("\(scoreData.score)")
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