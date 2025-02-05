import Foundation
import CoreData

// Register value transformer for [String: Int32]
@objc(ScoresDictionaryValueTransformer)
final class ScoresDictionaryValueTransformer: NSSecureUnarchiveFromDataTransformer {
    
    static let name = NSValueTransformerName(rawValue: "ScoresDictionaryValueTransformer")
    
    override static var allowedTopLevelClasses: [AnyClass] {
        [NSDictionary.self, NSString.self, NSNumber.self]
    }
    
    public static func register() {
        let transformer = ScoresDictionaryValueTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}

@objc(Round)
public class Round: NSManagedObject {
    // MARK: - Constants
    private static let minRoundNumber: Int16 = 1
    private static let maxRoundNumber: Int16 = 12
    
    // MARK: - Validation Errors
    enum ValidationError: LocalizedError {
        case invalidRoundNumber(Int16)
        case invalidDealerIndex(Int16)
        case invalidScores([String: Int32])
        case missingGame
        case incompleteScores(Set<String>)
        case invalidPlayerReference(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidRoundNumber(let number):
                return "Invalid round number: \(number). Must be between \(Round.minRoundNumber) and \(Round.maxRoundNumber)"
            case .invalidDealerIndex(let index):
                return "Invalid dealer index: \(index)"
            case .invalidScores(let scores):
                return "Invalid scores: \(scores)"
            case .missingGame:
                return "Round must be associated with a game"
            case .incompleteScores(let missing):
                return "Missing scores for players: \(missing.joined(separator: ", "))"
            case .invalidPlayerReference(let id):
                return "Invalid player reference: \(id)"
            }
        }
    }
    
    // MARK: - Factory Methods
    static func createRound(number: Int16, dealerIndex: Int16, context: NSManagedObjectContext) throws -> Round {
        // Validate input
        try validateRoundCreation(number: number, dealerIndex: dealerIndex)
        
        // Create round
        let round = Round(context: context)
        round.id = UUID()
        round.number = number
        round.dealerIndex = dealerIndex
        round.isCompleted = false
        round.scores = [:]
        
        return round
    }
    
    // MARK: - Validation
    private static func validateRoundCreation(number: Int16, dealerIndex: Int16) throws {
        // Validate round number
        guard number >= minRoundNumber && number <= maxRoundNumber else {
            throw ValidationError.invalidRoundNumber(number)
        }
        
        // Validate dealer index
        guard dealerIndex >= 0 else {
            throw ValidationError.invalidDealerIndex(dealerIndex)
        }
    }
    
    func validateState() throws {
        // Validate basic properties
        guard id != UUID.init() else {
            throw ValidationError.invalidRoundNumber(number)
        }
        
        guard number >= Self.minRoundNumber && number <= Self.maxRoundNumber else {
            throw ValidationError.invalidRoundNumber(number)
        }
        
        guard dealerIndex >= 0 else {
            throw ValidationError.invalidDealerIndex(dealerIndex)
        }
        
        // Validate game relationship
        guard game != nil else {
            throw ValidationError.missingGame
        }
        
        // Validate scores
        if isCompleted {
            let playerIds = game?.playersArray.map { $0.id.uuidString } ?? []
            let scoreKeys = scores?.keys.map { String($0) } ?? []
            let missingScores = Set(playerIds).subtracting(Set(scoreKeys))
            
            if !missingScores.isEmpty {
                throw ValidationError.incompleteScores(missingScores)
            }
            
            // Validate individual scores
            if let scores = scores {
                for (playerId, score) in scores {
                    guard score >= 0 && score <= maximumScore else {
                        throw ValidationError.invalidScores(scores)
                    }
                    
                    // Verify player exists
                    guard game?.playersArray.contains(where: { $0.id.uuidString == playerId }) ?? false else {
                        throw ValidationError.invalidPlayerReference(playerId)
                    }
                }
            }
        }
    }
    
    // MARK: - Score Management
    func updateScore(for player: Player, score: Int32) throws {
        guard let game = game,
              let players = game.players as? Set<Player>,
              players.contains(player) else {
            throw ValidationError.invalidPlayerReference(player.id.uuidString)
        }
        
        guard score >= 0 else {
            throw ValidationError.invalidScores([player.id.uuidString: score])
        }
        
        var currentScores = scores ?? [:]
        currentScores[player.id.uuidString] = score
        scores = currentScores
        
        // If all players have scores, mark as completed
        if Set(currentScores.keys) == Set(players.map { $0.id.uuidString }) {
            isCompleted = true
            try validateState()
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        scores = nil
        game = nil
    }
} 
