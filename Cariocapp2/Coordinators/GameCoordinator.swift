import Foundation
import CoreData
import SwiftUI

enum GameCoordinatorError: LocalizedError {
    case deletionFailed
    case gameNotFound
    case invalidState
    case transactionFailed
    case saveFailed(Error)
    case roundCreationFailed(Error)
    case scoreUpdateFailed(Error)
    case gameCompletionFailed(Error)
    case concurrencyError(String)
    case invalidPlayerCount
    case contextError(String)
    case noPlayersSelected
    case roundNotFound
    
    var errorDescription: String? {
        switch self {
        case .deletionFailed:
            return "Failed to delete game"
        case .gameNotFound:
            return "Game not found"
        case .invalidState:
            return "Game is in an invalid state"
        case .transactionFailed:
            return "Transaction failed"
        case .saveFailed(let error):
            return "Failed to save changes: \(error.localizedDescription)"
        case .roundCreationFailed(let error):
            return "Failed to create new round: \(error.localizedDescription)"
        case .scoreUpdateFailed(let error):
            return "Failed to update scores: \(error.localizedDescription)"
        case .gameCompletionFailed(let error):
            return "Failed to complete game: \(error.localizedDescription)"
        case .concurrencyError(let message):
            return "Concurrency error: \(message)"
        case .invalidPlayerCount:
            return "Invalid number of players. Must be between 2 and 4 players."
        case .contextError(let message):
            return "Context error: \(message)"
        case .noPlayersSelected:
            return "No players selected for the game"
        case .roundNotFound:
            return "Round not found"
        }
    }
}

// MARK: - Game Creation Data
struct PlayerData {
    let id: String
    let name: String
    let isGuest: Bool
}

struct NewGameData {
    let players: [PlayerData]
    let dealerIndex: Int16
}

@MainActor
class GameCoordinator: ObservableObject {
    // MARK: - Shared Instance
    static let shared = GameCoordinator(viewContext: PersistenceController.shared.container.viewContext)
    
    // MARK: - Published Properties
    @Published private(set) var gameID: UUID?
    @Published private(set) var isDeleting = false
    @Published private(set) var shouldDismiss = false
    @Published private(set) var error: Error?
    @Published private(set) var isProcessing = false
    @Published var shouldNavigateToNewGame = false
    @Published var path: [AppDestination] = []
    @Published var viewContext: NSManagedObjectContext
    
    // MARK: - Properties
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 0.5
    
    // MARK: - Initialization
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
    // MARK: - Navigation Control
    func setShouldDismiss(_ value: Bool) {
        shouldDismiss = value
    }
    
    func dismissSheet() {
        shouldDismiss = true
    }
    
    func popToRoot() {
        path.removeAll()
    }
    
    // MARK: - Context Management
    func updateContext(_ newContext: NSManagedObjectContext) {
        guard newContext != viewContext else { return }
        viewContext = newContext
    }
    
    // MARK: - Transaction Management
    private func performTransaction<T>(_ operation: @escaping (NSManagedObjectContext) async throws -> T) async throws -> T {
        for attempt in 1...maxRetryAttempts {
            do {
                let result = try await operation(viewContext)
                if viewContext.hasChanges {
                    try await viewContext.save()
                }
                return result
            } catch {
                if attempt == maxRetryAttempts {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        throw GameCoordinatorError.transactionFailed
    }
    
    // MARK: - Game Creation
    func createGame(players: [Player], guestPlayers: [(id: UUID, name: String)], dealerIndex: Int16) async throws -> Game {
        print("🎮 Creating game with \(players.count) players and \(guestPlayers.count) guests")
        
        // Validate total player count
        let totalPlayers = players.count + guestPlayers.count
        guard totalPlayers >= 2 && totalPlayers <= 4 else {
            throw GameCoordinatorError.invalidPlayerCount
        }
        
        return try await performTransaction { context in
            print("🎮 Starting game creation transaction")
            
            // Validate registered players first
            for player in players {
                guard player.canJoinGame() else {
                    print("❌ Player \(player.name) has active games: \(player.activeGames.map { $0.id })")
                    throw AppError.invalidPlayerState("Player \(player.name) is already in an active game")
                }
                try player.validateState()
            }
            
            // Create game
            print("🎮 Creating game object")
            let game = Game(context: context)
            // Create a new UUID to avoid bridging issues
            let gameID = UUID()
            game.id = gameID
            game.startDate = Date()
            game.currentRound = 1
            game.dealerIndex = dealerIndex
            game.isActive = true
            
            // Add all players to the game
            game.players = NSSet(array: players)
            
            // Create initial round
            print("🎮 Creating initial round")
            let round = Round(context: context)
            // Create a new UUID for the round to avoid bridging issues
            round.id = UUID()
            round.number = 1
            round.dealerIndex = dealerIndex
            round.isCompleted = false
            round.isSkipped = false
            round.scores = [:]
            round.game = game
            
            // Validate the entire game state
            do {
                try game.validateState()
                print("🎮 Game state validated successfully")
            } catch {
                print("❌ Game validation failed: \(error)")
                context.rollback()
                throw error
            }
            
            // Save context to ensure everything is persisted
            do {
                try context.save()
                print("🎮 Game creation transaction completed successfully")
            } catch {
                print("❌ Failed to save game: \(error)")
                context.rollback()
                throw GameCoordinatorError.saveFailed(error)
            }
            
            return game
        }
    }
    
    // MARK: - Game State Management
    func updateGameState(_ game: Game, currentRound: Int16, dealerIndex: Int16) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        try await performTransaction { [weak self] context in
            guard let self = self else { throw GameCoordinatorError.transactionFailed }
            
            if let gameToUpdate = try await self.verifyGame(id: game.id, in: context) {
                // Validate round number
                guard currentRound > 0 && currentRound <= Int16(gameToUpdate.maxRounds) else {
                    throw AppError.invalidGameState("Invalid round number: \(currentRound)")
                }
                
                // Update game state
                gameToUpdate.currentRound = currentRound
                gameToUpdate.dealerIndex = dealerIndex
                
                // Ensure all previous rounds exist
                let existingRounds = gameToUpdate.roundsArray
                for roundNumber in 1...currentRound {
                    if !existingRounds.contains(where: { $0.number == roundNumber }) {
                        let round = try Round.createRound(
                            number: roundNumber,
                            dealerIndex: (gameToUpdate.dealerIndex + roundNumber - 1) % Int16(gameToUpdate.playersArray.count),
                            context: context
                        )
                        round.game = gameToUpdate
                        gameToUpdate.addToRounds(round)
                        
                        print("🎮 Created missing round \(roundNumber) with ID: \(round.id)")
                    }
                }
                
                // Save context to ensure rounds are persisted
                try context.save()
                
                // Verify rounds after creation
                print("🎮 Verifying rounds after update:")
                for round in gameToUpdate.roundsArray.sorted(by: { $0.number < $1.number }) {
                    print("🎮 Round \(round.number): completed=\(round.isCompleted), skipped=\(round.isSkipped), scores=\(round.scores ?? [:])")
                }
            } else {
                throw GameCoordinatorError.gameNotFound
            }
        }
    }
    
    func verifyGame(id: UUID, in context: NSManagedObjectContext? = nil) async throws -> Game? {
        let context = context ?? viewContext
        
        // Convert UUID to string to avoid bridging issues
        let idString = id.uuidString
        
        let fetchRequest = NSFetchRequest<Game>(entityName: "Game")
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        // Configure fetch request for optimal performance
        fetchRequest.relationshipKeyPathsForPrefetching = ["players", "rounds"]
        fetchRequest.returnsObjectsAsFaults = false
        
        // Fetch the game with all relationships
        guard let game = try context.fetch(fetchRequest).first else {
            return nil
        }
        
        // Force fault in all relationships and refresh from context
        context.refresh(game, mergeChanges: true)
        _ = game.players?.count
        _ = game.rounds?.count
        
        // Print detailed game state for debugging
        print("🎮 Game verification for game \(idString):")
        print("🎮 Current round: \(game.currentRound)")
        print("🎮 Dealer index: \(game.dealerIndex)")
        print("🎮 Is active: \(game.isActive)")
        
        // Validate players relationship
        guard let players = game.players as? Set<Player>, !players.isEmpty else {
            print("🎮 Game verification failed: No players found")
            return nil
        }
        print("🎮 Players: \(players.map { $0.name }.joined(separator: ", "))")
        
        // Log rounds state
        if let rounds = game.rounds as? Set<Round> {
            print("🎮 Found \(rounds.count) rounds:")
            let sortedRounds = rounds.sorted { $0.number < $1.number }
            for round in sortedRounds {
                print("🎮 Round \(round.number): completed=\(round.isCompleted), skipped=\(round.isSkipped), scores=\(round.scores ?? [:])")
            }
        } else {
            print("🎮 No rounds found")
        }
        
        return game
    }
    
    func deleteGame(_ game: Game) async throws {
        // Call cleanup before deletion
        game.cleanup()
        viewContext.delete(game)
        try viewContext.save()
    }
    
    func completeGame(_ gameID: UUID) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        try await performTransaction { [weak self] context in
            guard let self = self else { throw GameCoordinatorError.transactionFailed }
            
            if let gameToComplete = try await self.verifyGame(id: gameID, in: context) {
                print("🎮 Completing game: \(gameID)")
                
                // Calculate final scores and create snapshot first
                let scores = calculateFinalScores(for: gameToComplete)
                let sortedPlayers = scores.sorted { $0.value < $1.value }
                
                // Create game snapshot before updating any state
                gameToComplete.createSnapshot()
                
                // Update player statistics
                for (index, playerScore) in sortedPlayers.enumerated() {
                    if let player = gameToComplete.playersArray.first(where: { $0.id.uuidString == playerScore.key }) {
                        print("🎮 Updating stats for player: \(player.name)")
                        player.gamesPlayed += 1
                        if index == 0 {
                            player.gamesWon += 1
                        }
                        player.totalScore += Int32(playerScore.value)
                        
                        let position = Double(index + 1)
                        if player.gamesPlayed == 1 {
                            player.averagePosition = position
                        } else {
                            let oldTotal = player.averagePosition * Double(player.gamesPlayed - 1)
                            player.averagePosition = (oldTotal + position) / Double(player.gamesPlayed)
                        }
                    }
                }
                
                // Save changes before marking game as inactive
                try context.save()
                
                // Mark game as inactive and set end date
                gameToComplete.isActive = false
                gameToComplete.endDate = Date()
                
                // Final save
                try context.save()
                print("🎮 Game completed successfully")
                
            } else {
                throw GameCoordinatorError.gameNotFound
            }
        }
    }
    
    // MARK: - Score Management
    func submitScores(gameID: UUID, scores: [String: Int32]) async throws {
        try await performTransaction { [weak self] context in
            guard let self = self else { throw GameCoordinatorError.transactionFailed }
            
            // 1. Fetch the game with a fresh context
            let fetchRequest = NSFetchRequest<Game>(entityName: "Game")
            fetchRequest.predicate = NSPredicate(format: "id == %@", gameID as CVarArg)
            fetchRequest.relationshipKeyPathsForPrefetching = ["rounds", "players"]
            
            guard let game = try context.fetch(fetchRequest).first else {
                throw AppError.invalidGameState("Game not found")
            }
            
            print("🎮 Submitting scores for round \(game.currentRound)")
            
            // 2. Find or create the current round
            guard let round = game.roundsArray.first(where: { $0.number == game.currentRound }) else {
                throw AppError.invalidGameState("Current round not found")
            }
            
            // 3. Update the round with scores
            round.scores = scores
            round.isCompleted = true
            round.isSkipped = false
            
            // Save to ensure scores are persisted
            try context.save()
            
            // 4. Check if this was the last round (12)
            if game.currentRound == 12 {
                print("🎮 Round 12 completed, checking game completion")
                // Complete the game
                try await completeGame(gameID)
            } else if game.currentRound < Int16(game.maxRounds) {
                // 5. If not the last round, advance to next round
                game.currentRound += 1
                game.dealerIndex = (game.dealerIndex + 1) % Int16(game.playersArray.count)
                
                // Create next round if it doesn't exist
                if !game.roundsArray.contains(where: { $0.number == game.currentRound }) {
                    let nextRound = Round(context: context)
                    nextRound.id = UUID()
                    nextRound.number = game.currentRound
                    nextRound.dealerIndex = game.dealerIndex
                    nextRound.isCompleted = false
                    nextRound.isSkipped = false
                    nextRound.scores = [:]
                    nextRound.game = game
                }
                
                try context.save()
            }
        }
    }
    
    // MARK: - Round Management
    func skipRound(gameID: UUID) async throws {
        try await performTransaction { [weak self] context in
            guard let self = self else { throw GameCoordinatorError.transactionFailed }
            
            guard let game = try await self.verifyGame(id: gameID, in: context) else {
                throw AppError.invalidGameState("Game not found")
            }
            
            // Verify this is an optional round (9-11)
            guard game.currentRound >= 9 && game.currentRound <= 11 else {
                throw AppError.invalidGameState("Can only skip optional rounds (9-11)")
            }
            
            // Find or create the current round
            let round: Round
            
            // Try to find existing round with exact match
            if let existingRound = game.roundsArray.first(where: { 
                $0.number == game.currentRound && !$0.isCompleted && !$0.isSkipped 
            }) {
                round = existingRound
            } else {
                // Create new round
                round = try Round.createRound(
                    number: game.currentRound,
                    dealerIndex: Int16(game.dealerIndex),
                    context: context
                )
                round.game = game
                game.addToRounds(round)
            }
            
            // Mark as skipped and completed
            round.isSkipped = true
            round.isCompleted = true
            round.scores = [:]  // Empty scores for skipped round
            
            // Update game state for next round
            game.currentRound += 1
            game.dealerIndex = (game.dealerIndex + 1) % Int16(game.playersArray.count)
            
            // Create the next round if it doesn't exist
            if !game.roundsArray.contains(where: { $0.number == game.currentRound }) {
                let nextRound = try Round.createRound(
                    number: game.currentRound,
                    dealerIndex: game.dealerIndex,
                    context: context
                )
                nextRound.game = game
                game.addToRounds(nextRound)
            }
            
            return ()
        }
    }
    
    /// Get a round by its ID
    /// - Parameter id: The UUID of the round to retrieve
    /// - Returns: The Round object if found, nil otherwise
    func getRound(id roundID: UUID) async throws -> Round? {
        let request = Round.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", roundID as CVarArg)
        request.fetchLimit = 1
        
        return try await withCheckedThrowingContinuation { continuation in
            viewContext.perform {
                do {
                    let rounds = try request.execute()
                    continuation.resume(returning: rounds.first)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Get the current round for a game
    /// - Parameter gameID: The UUID of the game
    /// - Returns: The current Round object if found, nil otherwise
    func getCurrentRound(for gameID: UUID) async throws -> Round? {
        do {
            // Use the proper method to get the game
            let fetchRequest: NSFetchRequest<Game> = Game.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", gameID as CVarArg)
            fetchRequest.fetchLimit = 1
            
            let games = try viewContext.fetch(fetchRequest)
            guard let game = games.first else {
                throw GameCoordinatorError.gameNotFound
            }
            
            // Get the current round based on the game's currentRound property
            guard game.currentRound > 0 && game.currentRound <= Int16(game.roundsArray.count) else {
                return nil
            }
            
            return game.roundsArray[Int(game.currentRound) - 1]
        } catch {
            Logger.logError(error, category: Logger.game)
            return nil
        }
    }
    
    /// Update the scores for a specific round
    /// - Parameters:
    ///   - roundID: The UUID of the round to update
    ///   - scores: Dictionary mapping player IDs to scores
    /// - Returns: The updated Round object if successful, nil otherwise
    func updateRoundScores(roundID: UUID, scores: [String: Int32]) async throws -> Round? {
        guard let round = try await getRound(id: roundID) else {
            throw GameCoordinatorError.roundNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            viewContext.perform {
                do {
                    round.scores = scores
                    try self.viewContext.save()
                    continuation.resume(returning: round)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func calculateFinalScores(for game: Game) -> [String: Int] {
        var scores: [String: Int] = [:]
        
        // Get all completed rounds
        let completedRounds = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }
        print("📊 Calculating scores for \(game.roundsArray.count) total rounds")
        print("📊 Found \(completedRounds.count) completed rounds")
        print("📊 Completed rounds: \(completedRounds.map { "Round \($0.number)" }.joined(separator: ", "))")
        
        // Calculate total scores for each player
        for player in game.playersArray {
            print("📊 Calculating total for \(player.name) (ID: \(player.id.uuidString)):")
            var total = 0
            
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    print("  - Round \(round.number): \(score) points")
                    total += Int(score)
                }
            }
            
            print("📊 Final total for \(player.name): \(total) points")
            scores[player.id.uuidString] = total
        }
        
        return scores
    }
    
    private func updatePlayerStats(for game: Game) {
        // Calculate final positions
        let playerScores = calculateFinalScores(for: game)
        let sortedPlayers = playerScores.sorted { $0.value < $1.value }
        
        // Update each player's statistics
        for (index, playerScore) in sortedPlayers.enumerated() {
            if let player = game.playersArray.first(where: { $0.id.uuidString == playerScore.key }) {
                player.gamesPlayed += 1
                if index == 0 {
                    player.gamesWon += 1
                }
                player.totalScore += Int32(playerScore.value)
                
                let position = Double(index + 1)
                if player.gamesPlayed == 1 {
                    player.averagePosition = position
                } else {
                    let oldTotal = player.averagePosition * Double(player.gamesPlayed - 1)
                    player.averagePosition = (oldTotal + position) / Double(player.gamesPlayed)
                }
            }
        }
    }
    
    // MARK: - Error Recovery
    private func handleTransactionError(_ error: Error) {
        viewContext.rollback()
        self.error = error
    }
    
    // MARK: - Reset
    private func reset() {
        gameID = nil
        isDeleting = false
        shouldDismiss = false
        error = nil
        isProcessing = false
        shouldNavigateToNewGame = false
    }
    
    deinit {
        Task { @MainActor [weak self] in
            await self?.reset()
        }
    }
} 