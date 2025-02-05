import Foundation
import CoreData

extension Round {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Round> {
        return NSFetchRequest<Round>(entityName: "Round")
    }

    @NSManaged public var id: UUID
    @NSManaged public var number: Int16
    @NSManaged public var dealerIndex: Int16
    @NSManaged public var isCompleted: Bool
    @NSManaged public var isSkipped: Bool
    @NSManaged public var scores: [String: Int32]?
    @NSManaged public var game: Game?
    @NSManaged public var firstCardColor: String?
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        scores = [:]
        isCompleted = false
        isSkipped = false
        firstCardColor = nil
    }

    public var safeScores: [String: Int32] {
        get { scores ?? [:] }
        set { scores = newValue }
    }
    
    // MARK: - Public Properties
    public var name: String {
        if let rule = RoundRule.getRound(number: number) {
            return rule.name
        }
        return "Unknown Round"
    }
    
    public override var description: String {
        if let rule = RoundRule.getRound(number: number) {
            return rule.description
        }
        return "Unknown Round"
    }
    
    public var minimumCards: Int {
        if let rule = RoundRule.getRound(number: number) {
            return rule.minimumCards
        }
        return 0
    }
    
    public var maximumScore: Int32 {
        if let rule = RoundRule.getRound(number: number),
           let game = game {
            return rule.getMaximumScore(playerCount: game.playersArray.count)
        }
        return 0
    }
    
    // MARK: - Score Management
    public struct PlayerScore: Equatable {
        let player: Player
        let score: Int32
        
        public static func == (lhs: PlayerScore, rhs: PlayerScore) -> Bool {
            lhs.player.id == rhs.player.id && lhs.score == rhs.score
        }
    }
    
    public var sortedScores: [PlayerScore] {
        guard let game = game,
              let scores = scores else { return [] }
        
        let players = game.playersArray
        
        return players.compactMap { player in
            guard let score = scores[player.id.uuidString] else { return nil }
            return PlayerScore(player: player, score: score)
        }.sorted { $0.score > $1.score }
    }
    
    // MARK: - Score Management
    public func setScore(_ score: Int32, for player: Player) throws {
        guard !isCompleted else {
            throw AppError.invalidGameState("Cannot modify scores of a completed round")
        }
        
        guard score >= 0 && score <= maximumScore else {
            throw AppError.invalidGameState("Invalid score: \(score). Maximum allowed: \(maximumScore)")
        }
        
        safeScores[player.id.uuidString] = score
    }
    
    public func getScore(for player: Player) -> Int32 {
        safeScores[player.id.uuidString, default: 0]
    }
    
    public func completeRound() throws {
        try validate()
        isCompleted = true
    }
    
    // MARK: - Validation
    public func validate() throws {
        // Validate basic properties
        guard id != UUID.init() else {
            throw AppError.invalidGameState("Round ID is invalid")
        }
        
        guard let game = game else {
            throw AppError.invalidGameState("Round is not associated with a game")
        }
        
        // Get ordered rounds
        let orderedRounds = RoundRule.getOrderedRounds()
        let validRoundNumbers = Set(orderedRounds.map { $0.roundNumber })
        
        // Validate round number
        guard validRoundNumbers.contains(number) else {
            throw AppError.invalidGameState("Invalid round number: \(number)")
        }
        
        // Validate dealer index
        guard dealerIndex >= 0 && dealerIndex < Int16(game.playersArray.count) else {
            throw AppError.invalidGameState("Invalid dealer index: \(dealerIndex)")
        }
        
        // If round is skipped, no need to validate scores
        if isSkipped {
            return
        }
        
        // Validate scores
        let players = game.playersArray
        let playerIds = Set(players.map { $0.id.uuidString })
        let scoreIds = Set(safeScores.keys)
        
        // Check if all players have scores
        guard playerIds == scoreIds else {
            throw AppError.invalidGameState("Not all players have scores")
        }
        
        // Validate individual scores
        for (_, score) in safeScores {
            guard score >= 0 && score <= maximumScore else {
                throw AppError.invalidGameState("Invalid score value: \(score)")
            }
        }
        
        // Check if at least one player has a score of 0 (winner)
        guard safeScores.values.contains(0) else {
            throw AppError.invalidGameState("No winning score (0) found")
        }
    }
}

extension Round: Identifiable {} 