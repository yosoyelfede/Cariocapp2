import Foundation

public struct RoundRule: Identifiable, Hashable {
    // MARK: - Properties
    public let id = UUID()
    public let name: String
    public let description: String
    public let isOptional: Bool
    public let minimumCards: Int
    public var roundNumber: Int16
    
    // MARK: - Constants
    private static let maxRoundNumber: Int16 = 12
    private static let minRoundNumber: Int16 = 1
    
    // MARK: - Static Properties
    public static let allRounds: [RoundRule] = [
        RoundRule(roundNumber: 1, name: "2 Trios", description: "Make two groups of three cards each", minimumCards: 6, isOptional: false),
        RoundRule(roundNumber: 2, name: "1 Trio + 1 Straight", description: "Make one group of three cards and one straight", minimumCards: 6, isOptional: false),
        RoundRule(roundNumber: 3, name: "2 Straights", description: "Make two straights", minimumCards: 6, isOptional: false),
        RoundRule(roundNumber: 4, name: "3 Trios", description: "Make three groups of three cards each", minimumCards: 9, isOptional: false),
        RoundRule(roundNumber: 5, name: "2 Trios + 1 Straight", description: "Make two groups of three cards and one straight", minimumCards: 9, isOptional: false),
        RoundRule(roundNumber: 6, name: "1 Trio + 2 Straights", description: "Make one group of three cards and two straights", minimumCards: 9, isOptional: false),
        RoundRule(roundNumber: 7, name: "3 Straights", description: "Make three straights", minimumCards: 9, isOptional: false),
        RoundRule(roundNumber: 8, name: "4 Trios", description: "Make four groups of three cards each", minimumCards: 12, isOptional: false),
        RoundRule(roundNumber: 9, name: "Escala Sucia", description: "Make a dirty straight", minimumCards: 12, isOptional: true),
        RoundRule(roundNumber: 10, name: "Escala Color", description: "Make a straight of the same color", minimumCards: 12, isOptional: true),
        RoundRule(roundNumber: 11, name: "Escala Bicolor", description: "Make a straight with alternating colors", minimumCards: 12, isOptional: true),
        RoundRule(roundNumber: 12, name: "Escala Real", description: "Make four straights", minimumCards: 12, isOptional: false)
    ]
    
    // MARK: - Initialization
    public init(roundNumber: Int16, name: String, description: String, minimumCards: Int, isOptional: Bool) {
        self.roundNumber = roundNumber
        self.name = name
        self.description = description
        self.minimumCards = minimumCards
        self.isOptional = isOptional
    }
    
    // MARK: - Static Methods
    public static func getRound(number: Int16) -> RoundRule? {
        allRounds.first { $0.roundNumber == number }
    }
    
    static func getRequiredRounds() -> [RoundRule] {
        allRounds.filter { !$0.isOptional }
    }
    
    static func getOptionalRounds() -> [RoundRule] {
        allRounds.filter { $0.isOptional }
    }
    
    static func getOrderedRounds() -> [RoundRule] {
        return allRounds
    }
    
    static func validateRoundNumber(_ number: Int16) -> Bool {
        number >= minRoundNumber && number <= maxRoundNumber
    }
    
    // MARK: - Instance Methods
    func getMaximumScore(playerCount: Int) -> Int32 {
        return 999  // Static maximum that will never be reached in practice
    }
    
    // MARK: - Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(roundNumber)
    }
    
    public static func == (lhs: RoundRule, rhs: RoundRule) -> Bool {
        lhs.id == rhs.id && lhs.roundNumber == rhs.roundNumber
    }
} 