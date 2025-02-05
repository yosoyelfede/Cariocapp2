import Foundation
import CoreData

extension Game {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Game> {
        return NSFetchRequest<Game>(entityName: "Game")
    }

    @NSManaged public var id: UUID
    @NSManaged public var startDate: Date
    @NSManaged public var endDate: Date?
    @NSManaged public var currentRound: Int16
    @NSManaged public var dealerIndex: Int16
    @NSManaged public var isActive: Bool
    @NSManaged public var players: NSSet?
    @NSManaged public var rounds: NSSet?
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        startDate = Date()
        currentRound = 1
        dealerIndex = 0
        isActive = true
    }
    
    // MARK: - Public Properties
    public var playersArray: [Player] {
        guard let allObjects = players?.allObjects else { return [] }
        return (allObjects as? [Player])?.sorted { $0.name < $1.name } ?? []
    }
    
    public var roundsArray: [Round] {
        guard let allObjects = rounds?.allObjects else { return [] }
        let roundsArray = (allObjects as? [Round])?.sorted { $0.number < $1.number } ?? []
        print("🎲 Game \(id) - Fetched \(roundsArray.count) rounds: \(roundsArray.map { "Round \($0.number)" }.joined(separator: ", "))")
        return roundsArray
    }
    
    public var dealer: Player? {
        let players = playersArray
        guard !players.isEmpty else { return nil }
        return players[Int(dealerIndex) % players.count]
    }
    
    public var starter: Player? {
        let players = playersArray
        guard !players.isEmpty else { return nil }
        let starterIndex = (Int(dealerIndex) + 1) % players.count
        return players[starterIndex]
    }
    
    public var name: String {
        "Round \(currentRound)"
    }
    
    public var sortedRounds: [Round] {
        roundsArray
    }
    
    public var maxRounds: Int {
        return 12  // Fixed number of rounds, with optional ones being skippable
    }
    
    public var cardColorStats: (redPercentage: Double, blackPercentage: Double) {
        // Get completed, non-skipped rounds
        let completedRounds = roundsArray.filter { $0.isCompleted && !$0.isSkipped }
        let roundsWithColor = completedRounds.filter { $0.firstCardColor != nil }
        let totalRounds = Double(roundsWithColor.count)
        guard totalRounds > 0 else { return (0, 0) }
        
        // Count rounds with each color
        let redRounds = Double(roundsWithColor.filter { $0.firstCardColor == FirstCardColor.red.rawValue }.count)
        let blackRounds = Double(roundsWithColor.filter { $0.firstCardColor == FirstCardColor.black.rawValue }.count)
        
        // Calculate percentages
        return (
            redPercentage: (redRounds / totalRounds) * 100,
            blackPercentage: (blackRounds / totalRounds) * 100
        )
    }
    
    public var isComplete: Bool {
        // Get all rounds and expected count
        let allRounds = roundsArray
        let expectedRoundCount = maxRounds
        
        // Game is complete if:
        // 1. We have rounds
        // 2. All non-skipped rounds are completed
        // 3. Current round is greater than max rounds (we've gone through all rounds)
        guard !allRounds.isEmpty,
              allRounds.allSatisfy({ $0.isCompleted }),
              currentRound > Int16(expectedRoundCount) else {
            return false
        }
        
        // Get all non-skipped rounds
        let nonSkippedRounds = allRounds.filter { !$0.isSkipped }
        
        // Verify we have all required rounds (1-8 and 12)
        let requiredRoundNumbers: Set<Int16> = [1, 2, 3, 4, 5, 6, 7, 8, 12]
        let actualRoundNumbers = Set(nonSkippedRounds.map { $0.number })
        
        // Check if we have all required rounds
        guard requiredRoundNumbers.isSubset(of: actualRoundNumbers) else {
            return false
        }
        
        // Check if optional rounds (9-11) are either skipped or completed
        let optionalRoundNumbers: Set<Int16> = [9, 10, 11]
        let optionalRounds = allRounds.filter { optionalRoundNumbers.contains($0.number) }
        
        guard optionalRounds.allSatisfy({ $0.isSkipped || $0.isCompleted }) else {
            return false
        }
        
        return true
    }
    
    public var currentRoundDescription: String {
        guard currentRound > 0 && currentRound <= maxRounds else { return "Invalid Round" }
        return roundsArray.first { $0.number == currentRound }?.description ?? "Unknown Round"
    }
    
    // MARK: - Validation
    public func validate() throws {
        // Validate basic properties
        guard id != UUID.init() else { throw AppError.invalidGameState("Game ID is invalid") }
        guard startDate <= Date() else { throw AppError.invalidGameState("Start date is in the future") }
        guard currentRound > 0 && currentRound <= Int16(maxRounds) else {
            throw AppError.invalidGameState("Invalid round number: \(currentRound)")
        }
        
        // Validate players
        let playerCount = playersArray.count
        guard playerCount >= 2 && playerCount <= 4 else {
            throw AppError.invalidGameState("Invalid number of players: \(playerCount)")
        }
        
        // Validate dealer index
        guard dealerIndex >= 0 && dealerIndex < Int16(playerCount) else {
            throw AppError.invalidGameState("Invalid dealer index: \(dealerIndex)")
        }
        
        // Validate rounds
        let roundCount = roundsArray.count
        guard roundCount <= maxRounds else {
            throw AppError.invalidGameState("Too many rounds: \(roundCount)")
        }
        
        // Validate round sequence
        let roundNumbers = Set(roundsArray.map { $0.number })
        guard roundNumbers.count == roundCount else {
            throw AppError.invalidGameState("Duplicate round numbers detected")
        }
        
        // Validate round completion
        for round in roundsArray where round.number < currentRound {
            guard round.isCompleted else {
                throw AppError.invalidGameState("Incomplete round: \(round.number)")
            }
        }
    }
    
    // MARK: - Game State Management
    public func advanceRound() throws {
        guard currentRound < Int16(maxRounds) else {
            throw AppError.invalidGameState("Cannot advance beyond max rounds")
        }
        
        guard let currentRoundObj = roundsArray.first(where: { $0.number == currentRound }),
              currentRoundObj.isCompleted else {
            throw AppError.invalidGameState("Current round is not complete")
        }
        
        currentRound += 1
        dealerIndex = Int16((Int(dealerIndex) + 1) % playersArray.count)
    }
    
    public func completeGame() throws {
        guard isComplete else {
            throw AppError.invalidGameState("Cannot complete game - not all rounds are finished")
        }
        
        isActive = false
        
        // Update player statistics
        for player in playersArray {
            player.updateStatistics()
        }
    }
}

extension Game: Identifiable {} 