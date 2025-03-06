import SwiftUI
import CoreData

// MARK: - Navigation Destinations
enum AppDestination: Hashable {
    case newGame
    case game(UUID)
    case gameCompletion(UUID)
    case players
    case rules
    case statistics
    case gameHistory
}

// MARK: - Sheet Presentations
enum AppSheet: Identifiable {
    case scoreEntry(gameID: UUID)
    case gameMenu(gameID: UUID)
    case gameCompletion(gameID: UUID)
    
    var id: String {
        switch self {
        case .scoreEntry(let gameID):
            return "scoreEntry-\(gameID)"
        case .gameMenu(let gameID):
            return "gameMenu-\(gameID)"
        case .gameCompletion(let gameID):
            return "gameCompletion-\(gameID)"
        }
    }
}

// MARK: - Navigation Coordinator
@MainActor
final class NavigationCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var path: [AppDestination] = []
    @Published var presentedSheet: AppSheet?
    @Published private(set) var isNavigating = false
    
    // MARK: - Properties
    private var viewContext: NSManagedObjectContext
    private var navigationInProgress = false
    
    // MARK: - Initialization
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    // MARK: - Navigation Methods
    func navigateToGame(_ gameID: UUID) {
        withAnimation(.easeInOut) {
            path.append(.game(gameID))
        }
    }
    
    func navigateToGameSummary(_ gameID: UUID) {
        withAnimation(.easeInOut) {
            // If we're already deep in navigation, pop to root first
            if path.count > 1 {
                path.removeAll()
                
                // Use a slight delay to make the transition smoother
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut) {
                        self.path.append(.gameCompletion(gameID))
                    }
                }
            } else {
                path.append(.gameCompletion(gameID))
            }
        }
    }
    
    func presentGameMenu(for gameID: UUID) {
        withAnimation(.easeInOut) {
            presentedSheet = .gameMenu(gameID: gameID)
        }
    }
    
    func presentScoreEntry(for gameID: UUID) {
        withAnimation(.easeInOut) {
            presentedSheet = .scoreEntry(gameID: gameID)
        }
    }
    
    func presentScoreEdit(for gameID: UUID) {
        withAnimation(.easeInOut) {
            presentedSheet = .scoreEntry(gameID: gameID)
        }
    }
    
    func dismissSheet() {
        withAnimation(.easeInOut) {
            presentedSheet = nil
        }
    }
    
    func popToRoot() {
        guard !navigationInProgress else { return }
        navigationInProgress = true
        
        withAnimation(.easeInOut) {
            path.removeAll()
            
            // Reset the flag after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.navigationInProgress = false
            }
        }
    }
    
    func pop() {
        guard !navigationInProgress && !path.isEmpty else { return }
        navigationInProgress = true
        
        withAnimation(.easeInOut) {
            path.removeLast()
            
            // Reset the flag after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.navigationInProgress = false
            }
        }
    }
    
    // MARK: - Game Flow Methods
    func completeGame(_ gameID: UUID) async throws {
        guard let game = try await fetchGame(gameID) else { return }
        
        // Create player snapshots for the game
        game.createSnapshot()
        
        // Mark game as inactive and set end date
        game.isActive = false
        game.endDate = Date()
        
        // Update statistics for all players in the game
        for player in game.playersArray {
            player.updateStatistics()
        }
        
        // Save changes
        try viewContext.save()
        
        // Update navigation
        await MainActor.run {
            // Clear any presented sheets
            withAnimation(.easeInOut) {
                presentedSheet = nil
            }
            
            // Pop to root with animation
            withAnimation(.easeInOut) {
                path.removeAll()
            }
        }
    }
    
    func refreshGameState(_ gameID: UUID) async throws {
        let game = try await fetchGame(gameID)
        if game != nil {
            // Notify any observers that the game state has changed
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }
    
    // MARK: - Game Management
    func deleteGame(_ gameID: UUID) async throws {
        guard let game = try await fetchGame(gameID) else { return }
        game.cleanup()
        viewContext.delete(game)
        try viewContext.save()
    }
    
    func getGame(id gameID: UUID) -> Game? {
        let request = Game.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", gameID as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    // MARK: - Context Management
    func updateContext(_ newContext: NSManagedObjectContext) {
        viewContext = newContext
    }
    
    // MARK: - Helper Methods
    private func fetchGame(_ id: UUID) async throws -> Game? {
        let request = Game.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try viewContext.fetch(request).first
    }
    
    // MARK: - Statistics Methods
    // These methods are no longer needed as we're using the player's updateStatistics() method
    private func calculatePlayerScores(for game: Game) -> [(player: Player, score: Int32)] {
        var totalScores: [(player: Player, score: Int32)] = []
        
        // Get all completed rounds
        let completedRounds = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }
        
        // Calculate total scores for each player
        for player in game.playersArray {
            var total: Int32 = 0
            
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    total += score
                }
            }
            
            totalScores.append((player: player, score: total))
        }
        
        // Sort by score (ascending)
        return totalScores.sorted { $0.score < $1.score }
    }
    
    private func updatePlayerStatistics(for game: Game, with playerScores: [(player: Player, score: Int32)]) {
        // This method is now deprecated - we use player.updateStatistics() directly
        // Left for reference
    }
    
    private func calculatePlayerStatistics(for player: Player, index: Int, score: Int32) -> (gamesPlayed: Int32, gamesWon: Int32, totalScore: Int32, position: Double) {
        // This method is now deprecated - we use player.updateStatistics() directly
        // Left for reference
        return (
            gamesPlayed: player.gamesPlayed,
            gamesWon: player.gamesWon,
            totalScore: player.totalScore,
            position: player.averagePosition
        )
    }
    
    private func updatePlayerStatistics(_ player: Player, stats: (gamesPlayed: Int32, gamesWon: Int32, totalScore: Int32, position: Double)) {
        // This method is now deprecated - we use player.updateStatistics() directly
        // Left for reference
    }
} 
