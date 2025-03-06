import Foundation
import CoreData

@objc(Game)
public class Game: NSManagedObject {
    // MARK: - Constants
    static let entityName = "Game"
    static let maxRounds = 12
    
    override public class func entity() -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: entityName, in: PersistenceController.shared.container.viewContext)!
    }
    
    private static let minPlayers = 2
    private static let maxPlayers = 4
    private static let initialRoundNumber: Int16 = 1
    
    // MARK: - Validation Errors
    enum ValidationError: LocalizedError {
        case invalidPlayerCount(Int)
        case invalidDealerIndex(Int16, playerCount: Int)
        case invalidRoundNumber(Int16)
        case missingRounds
        case duplicatePlayer(UUID)
        case invalidStartDate
        
        var errorDescription: String? {
            switch self {
            case .invalidPlayerCount(let count):
                return "Invalid number of players: \(count). Must be between 2 and 4"
            case .invalidDealerIndex(let index, let count):
                return "Invalid dealer index: \(index). Must be between 0 and \(count - 1)"
            case .invalidRoundNumber(let number):
                return "Invalid round number: \(number)"
            case .missingRounds:
                return "Game must have at least one round"
            case .duplicatePlayer(let id):
                return "Duplicate player with ID: \(id)"
            case .invalidStartDate:
                return "Game start date is invalid"
            }
        }
    }
    
    // MARK: - Static Methods
    static func createGame(players: [Player], dealerIndex: Int16, context: NSManagedObjectContext) throws -> Game {
        // Clean up any abandoned games first
        try cleanupAbandonedGames(in: context)
        
        // Clean up any active games for the selected players
        try cleanupActiveGames(for: players, in: context)
        
        // Validate input
        try validateGameCreation(players: players, dealerIndex: dealerIndex)
        
        // Create new game
        let game = Game(context: context)
        game.id = UUID()
        game.startDate = Date()
        game.currentRound = initialRoundNumber
        game.dealerIndex = dealerIndex
        game.isActive = true
        
        // Add players
        let playersSet = NSSet(array: players)
        game.players = playersSet
        
        // Create initial round
        let round = Round(context: context)
        round.id = UUID()
        round.number = initialRoundNumber
        round.dealerIndex = dealerIndex
        round.isCompleted = false
        round.isSkipped = false
        round.scores = [:]
        round.game = game
        
        // Add round to game
        game.addToRounds(round)
        
        // Validate initial state
        try game.validateState()
        
        return game
    }
    
    static func cleanupActiveGames(for players: [Player], in context: NSManagedObjectContext) throws {
        print("🎮 Cleaning up active games for players")
        
        // Fetch all active games that include any of the selected players
        let request = NSFetchRequest<Game>(entityName: Game.entityName)
        let playerIds = players.map { $0.id.uuidString }
        request.predicate = NSPredicate(format: "isActive == YES AND ANY players.id IN %@", playerIds)
        
        let activeGames = try context.fetch(request)
        print("🎮 Found \(activeGames.count) active games to clean up")
        
        for game in activeGames {
            print("🎮 Cleaning up active game: \(game.id)")
            // Mark game as inactive
            game.isActive = false
            game.endDate = Date()
            
            // Clear relationships
            if let gamePlayers = game.players as? Set<Player> {
                for player in gamePlayers {
                    print("🎮 Removing game from player: \(player.name)")
                    if let playerGames = player.games as? Set<Game> {
                        player.games = playerGames.filter { $0 != game } as NSSet
                    }
                }
            }
            game.players = NSSet()
            
            // Delete the game
            context.delete(game)
        }
        
        // Save changes
        try context.save()
        print("🎮 Active games cleanup completed")
    }
    
    static func cleanupAbandonedGames(in context: NSManagedObjectContext) throws {
        print("🎮 Cleaning up abandoned games")
        let request = NSFetchRequest<Game>(entityName: Game.entityName)
        request.predicate = NSPredicate(format: "isActive == YES AND startDate < %@", Date().addingTimeInterval(-3600 * 24) as NSDate)
        
        let abandonedGames = try context.fetch(request)
        print("🎮 Found \(abandonedGames.count) abandoned games")
        
        for game in abandonedGames {
            print("🎮 Cleaning up abandoned game: \(game.id)")
            game.cleanup()
            context.delete(game)
        }
        
        try context.save()
        print("🎮 Abandoned games cleanup completed")
    }
    
    private static func validateGameCreation(players: [Player], dealerIndex: Int16) throws {
        // Check player count
        guard players.count >= minPlayers && players.count <= maxPlayers else {
            throw ValidationError.invalidPlayerCount(players.count)
        }
        
        // Check dealer index
        guard dealerIndex >= 0 && dealerIndex < Int16(players.count) else {
            throw ValidationError.invalidDealerIndex(dealerIndex, playerCount: players.count)
        }
        
        // Check for duplicate players
        let playerIds = players.map { $0.id }
        let uniqueIds = Set(playerIds)
        if uniqueIds.count != players.count {
            if let duplicateId = playerIds.first(where: { id in
                playerIds.filter { $0 == id }.count > 1
            }) {
                throw ValidationError.duplicatePlayer(duplicateId)
            }
        }
        
        // Validate each player
        for player in players {
            try player.validateState()
        }
    }
    
    // MARK: - Instance Methods
    func addToRounds(_ round: Round) {
        var currentRounds = mutableSetValue(forKey: "rounds")
        currentRounds.add(round)
    }
    
    func removeFromRounds(_ round: Round) {
        var currentRounds = mutableSetValue(forKey: "rounds")
        currentRounds.remove(round)
    }
    
    func addToPlayers(_ player: Player) {
        var currentPlayers = mutableSetValue(forKey: "players")
        currentPlayers.add(player)
    }
    
    func removeFromPlayers(_ player: Player) {
        var currentPlayers = mutableSetValue(forKey: "players")
        currentPlayers.remove(player)
    }
    
    // MARK: - Validation
    override public func validateForDelete() throws {
        // No validation needed during deletion
        try super.validateForDelete()
    }
    
    override public func validateForUpdate() throws {
        // Only validate active games that aren't being deleted
        if isActive && !isDeleted {
            try validateState()
        }
        try super.validateForUpdate()
    }
    
    func validateState() throws {
        // Skip validation for inactive games
        guard isActive else { return }
        
        // Validate basic properties
        guard id != UUID.init() else {
            throw ValidationError.invalidPlayerCount(0)
        }
        
        guard startDate <= Date() else {
            throw ValidationError.invalidStartDate
        }
        
        // Validate players
        guard let playersSet = players as? Set<Player>,
              !playersSet.isEmpty else {
            throw ValidationError.invalidPlayerCount(0)
        }
        
        let playerCount = playersSet.count
        guard playerCount >= Self.minPlayers && playerCount <= Self.maxPlayers else {
            throw ValidationError.invalidPlayerCount(playerCount)
        }
        
        // Validate dealer index
        guard dealerIndex >= 0 && dealerIndex < Int16(playerCount) else {
            throw ValidationError.invalidDealerIndex(dealerIndex, playerCount: playerCount)
        }
        
        // Validate rounds
        guard let roundsSet = rounds as? Set<Round>,
              !roundsSet.isEmpty else {
            throw ValidationError.missingRounds
        }
        
        // Validate round numbers
        let roundNumbers = roundsSet.map { $0.number }.sorted()
        guard roundNumbers.first == 1 else {
            throw ValidationError.invalidRoundNumber(roundNumbers.first ?? 0)
        }
        
        // Validate round sequence
        for (index, number) in roundNumbers.enumerated() {
            guard number == Int16(index + 1) else {
                throw ValidationError.invalidRoundNumber(number)
            }
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        print("🎮 Starting cleanup for game: \(id)")
        
        if let context = managedObjectContext {
            // Delete all rounds first
            if let rounds = rounds as? Set<Round> {
                for round in rounds {
                    print("🎮 Deleting round: \(round.number)")
                    round.scores = nil
                    context.delete(round)
                }
            }
            rounds = NSSet()
            
            // Clear snapshots
            playerSnapshots = nil
            
            // Clear player relationships and update player state
            if let gamePlayers = players as? Set<Player> {
                for player in gamePlayers {
                    print("🎮 Removing game from player: \(player.name)")
                    if var playerGames = player.games as? Set<Game> {
                        playerGames.remove(self)
                        player.games = playerGames as NSSet
                    }
                }
            }
            
            // Clear the game's players relationship
            players = NSSet()
            
            // Mark game as inactive
            isActive = false
            endDate = Date()
            
            print("🎮 Cleanup completed for game: \(id)")
            
            // Final save to ensure all changes are persisted
            try? context.save()
        }
    }
}

// MARK: - Preview Support
extension Game {
    static func createPreviewGame(in context: NSManagedObjectContext) throws -> Game {
        // Create players with full initialization
        let player1 = Player(context: context)
        player1.id = UUID()
        player1.name = "John"
        player1.gamesPlayed = 5
        player1.gamesWon = 2
        player1.averagePosition = 1.8
        player1.totalScore = 150
        player1.createdAt = Date()
        
        let player2 = Player(context: context)
        player2.id = UUID()
        player2.name = "Alice"
        player2.gamesPlayed = 3
        player2.gamesWon = 1
        player2.averagePosition = 2.0
        player2.totalScore = 120
        player2.createdAt = Date()
        
        let player3 = Player(context: context)
        player3.id = UUID()
        player3.name = "Bob"
        player3.gamesPlayed = 4
        player3.gamesWon = 0
        player3.averagePosition = 2.5
        player3.totalScore = 100
        player3.createdAt = Date()
        
        // Create and validate game
        let game = try createGame(
            players: [player1, player2, player3],
            dealerIndex: 0,
            context: context
        )
        
        // Save context to ensure all relationships are properly established
        try context.save()
        
        return game
    }
} 