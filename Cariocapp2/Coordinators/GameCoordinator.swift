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
final class GameCoordinator: ObservableObject {
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
            
            // Create guest players
            let guestPlayerObjects = try guestPlayers.map { guest -> Player in
                print("🎮 Creating guest player: \(guest.name)")
                let player = Player(context: context)
                player.id = guest.id
                player.name = guest.name
                player.isGuest = true
                player.createdAt = Date()
                player.gamesPlayed = 0
                player.gamesWon = 0
                player.totalScore = 0
                player.averagePosition = 0
                try player.validate() // Validate each guest player
                return player
            }
            
            // Create game
            print("🎮 Creating game object")
            let game = Game(context: context)
            game.id = UUID()
            game.startDate = Date()
            game.currentRound = 1
            game.dealerIndex = dealerIndex
            game.isActive = true
            
            // Add all players to the game
            let allPlayers = players + guestPlayerObjects
            game.players = NSSet(array: allPlayers)
            
            // Create initial round
            print("🎮 Creating initial round")
            let round = Round(context: context)
            round.id = UUID()
            round.number = 1
            round.dealerIndex = dealerIndex
            round.isCompleted = false
            round.isSkipped = false
            round.scores = [:]
            round.game = game
            
            // Validate the entire game state
            try game.validateState()
            print("🎮 Game state validated successfully")
            
            // Save context to ensure everything is persisted
            try context.save()
            print("🎮 Game creation transaction completed successfully")
            
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
        print("🎮 Game verification for game \(id):")
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
                // Update player statistics first
                self.updatePlayerStats(for: gameToComplete)
                
                // Mark game as inactive and set end date
                gameToComplete.isActive = false
                gameToComplete.endDate = Date()
                
                // Save changes
                try context.save()
                
                // Clear navigation state
                await MainActor.run {
                    self.shouldDismiss = true
                    self.path.removeAll()
                }
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
            
            // 2. Ensure all rounds up to the current round exist
            let currentRoundNumber = game.currentRound
            let existingRounds = game.roundsArray
            
            // Create any missing rounds between 1 and currentRound
            for roundNumber in 1...currentRoundNumber {
                if !existingRounds.contains(where: { $0.number == roundNumber }) {
                    let newRound = Round(context: context)
                    newRound.id = UUID()
                    newRound.number = roundNumber
                    newRound.dealerIndex = (game.dealerIndex + roundNumber - 1) % Int16(game.playersArray.count)
                    newRound.isCompleted = false
                    newRound.isSkipped = false
                    newRound.scores = [:]
                    newRound.game = game
                    print("🎮 Created missing round \(roundNumber)")
                }
            }
            
            // Save to ensure all rounds are persisted
            try context.save()
            
            // 3. Find the current round
            guard let round = game.roundsArray.first(where: { $0.number == currentRoundNumber }) else {
                throw AppError.invalidGameState("Current round not found after creation")
            }
            
            // 4. Update the round with scores
            round.scores = scores
            round.isCompleted = true
            round.isSkipped = false
            
            // Save to ensure scores are persisted
            try context.save()
            
            // 5. Update game state and create next round if needed
            if currentRoundNumber < Int16(game.maxRounds) {
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
            } else {
                game.isActive = false
            }
            
            // Final save to persist all changes
            try context.save()
            
            // 6. Print verification info
            print("📊 Verification after score submission:")
            print("📊 Game rounds count: \(game.roundsArray.count)")
            for r in game.roundsArray.sorted(by: { $0.number < $1.number }) {
                print("📊 Round \(r.number): completed=\(r.isCompleted), scores=\(r.scores ?? [:])")
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
            
            // Verify this is an optional round
            guard game.currentRound >= 9 && game.currentRound <= 11 else {
                throw AppError.invalidGameState("Can only skip optional rounds")
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
            
            // Create the next round if not the final round and doesn't exist
            if game.currentRound <= Int16(game.maxRounds) && 
               !game.roundsArray.contains(where: { $0.number == game.currentRound }) {
                let nextRound = try Round.createRound(
                    number: game.currentRound,
                    dealerIndex: game.dealerIndex,
                    context: context
                )
                nextRound.game = game
                game.addToRounds(nextRound)
            } else {
                // Mark game as inactive since we've completed all rounds
                game.isActive = false
            }
            
            return ()
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