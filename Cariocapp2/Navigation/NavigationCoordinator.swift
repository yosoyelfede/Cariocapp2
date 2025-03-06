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
        
        // Calculate final scores and update player statistics
        let playerScores = calculatePlayerScores(for: game)
        updatePlayerStatistics(for: game, with: playerScores)
        
        // Mark game as inactive and set end date
        game.isActive = false
        game.endDate = Date()
        
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
    private func calculatePlayerScores(for game: Game) -> [(player: Player, score: Int32)] {
        var totalScores: [(player: Player, score: Int32)] = []
        
        // Get all completed rounds
        let completedRounds = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }
        
        // Calculate total scores for each player
        for player in game.playersArray {
            var total: Int32 = 0
            
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    total += score  // No conversion needed
                }
            }
            
            totalScores.append((player: player, score: total))
        }
        
        // Sort by score (ascending)
        return totalScores.sorted { $0.score < $1.score }
    }
    
    private func updatePlayerStatistics(for game: Game, with playerScores: [(player: Player, score: Int32)]) {
        // Update each player's statistics
        for (index, playerScore) in playerScores.enumerated() {
            let stats = calculatePlayerStatistics(for: playerScore.player, index: index, score: playerScore.score)
            updatePlayerStatistics(playerScore.player, stats: stats)
        }
    }
    
    private func calculatePlayerStatistics(for player: Player, index: Int, score: Int32) -> (gamesPlayed: Int32, gamesWon: Int32, totalScore: Int32, position: Double) {
        return (
            gamesPlayed: player.gamesPlayed + 1,
            gamesWon: index == 0 ? player.gamesWon + 1 : player.gamesWon,
            totalScore: player.totalScore + score,
            position: Double(index + 1)
        )
    }
    
    private func updatePlayerStatistics(_ player: Player, stats: (gamesPlayed: Int32, gamesWon: Int32, totalScore: Int32, position: Double)) {
        player.gamesPlayed = stats.gamesPlayed
        player.gamesWon = stats.gamesWon
        player.totalScore = stats.totalScore
        
        if stats.gamesPlayed == 1 {
            player.averagePosition = stats.position
        } else {
            let oldTotal = player.averagePosition * Double(stats.gamesPlayed - 1)
            player.averagePosition = (oldTotal + stats.position) / Double(stats.gamesPlayed)
        }
    }
} 
