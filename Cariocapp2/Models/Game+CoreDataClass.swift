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
    func validateState() throws {
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
        print("🎲 Game \(id) - Starting cleanup")
        
        // Remove all rounds
        if let rounds = rounds as? Set<Round> {
            print("🎲 Game \(id) - Cleaning up \(rounds.count) rounds")
            rounds.forEach { round in
                removeFromRounds(round)
                round.cleanup()
                managedObjectContext?.delete(round)
            }
        }
        
        // Remove player relationships and delete guest players
        if let players = players {
            print("🎲 Game \(id) - Cleaning up relationships with \((players as? Set<Player>)?.count ?? 0) players")
            self.players = nil
            players.forEach { player in
                if let player = player as? Player {
                    if player.isGuest {
                        // Delete guest player
                        print("🎲 Game \(id) - Deleting guest player: \(player.name)")
                        managedObjectContext?.delete(player)
                    }
                }
            }
        }
        
        print("🎲 Game \(id) - Cleanup complete")
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