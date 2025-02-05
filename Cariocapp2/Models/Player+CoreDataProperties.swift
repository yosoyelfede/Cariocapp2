import Foundation
import CoreData

extension Player {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Player> {
        return NSFetchRequest<Player>(entityName: "Player")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var gamesPlayed: Int32
    @NSManaged public var gamesWon: Int32
    @NSManaged public var totalScore: Int32
    @NSManaged public var averagePosition: Double
    @NSManaged public var isGuest: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var games: NSSet?
    @NSManaged public var rounds: NSSet?
    
    // MARK: - Constants
    private static let maxNameLength = 30
    private static let minNameLength = 2
    private static let nameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9\\s'-]+$")
    
    // MARK: - Initialization
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        name = ""  // Add default name
        gamesPlayed = 0
        gamesWon = 0
        totalScore = 0
        averagePosition = 0
        isGuest = false
        createdAt = Date()  // Add creation date
    }
    
    // MARK: - Validation
    public func validate() throws {
        // Validate ID
        guard id != UUID.init() else {
            throw AppError.invalidPlayerState("Player ID is invalid")
        }
        
        // Validate name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.invalidPlayerState("Player name cannot be empty")
        }
        
        guard trimmedName.count >= Self.minNameLength else {
            throw AppError.invalidPlayerState("Name must be at least \(Self.minNameLength) characters")
        }
        
        guard trimmedName.count <= Self.maxNameLength else {
            throw AppError.invalidPlayerState("Name must be at most \(Self.maxNameLength) characters")
        }
        
        let range = NSRange(location: 0, length: trimmedName.utf16.count)
        guard Self.nameRegex.firstMatch(in: trimmedName, range: range) != nil else {
            throw AppError.invalidPlayerState("Name can only contain letters, numbers, spaces, hyphens, and apostrophes")
        }
        
        // Validate statistics
        guard gamesPlayed >= 0 else {
            throw AppError.invalidPlayerState("Games played cannot be negative")
        }
        
        guard gamesWon >= 0 else {
            throw AppError.invalidPlayerState("Games won cannot be negative")
        }
        
        guard gamesWon <= gamesPlayed else {
            throw AppError.invalidPlayerState("Games won cannot exceed games played")
        }
        
        guard averagePosition >= 0 && averagePosition <= 4 else {
            throw AppError.invalidPlayerState("Invalid average position")
        }
    }
    
    // MARK: - Computed Properties
    public var roundsArray: [Round] {
        let allObjects = rounds?.allObjects ?? []
        return (allObjects as? [Round])?.sorted { $0.number < $1.number } ?? []
    }
    
    // MARK: - Statistics
    public var scores: [Int32] {
        get {
            var allScores: [Int32] = []
            for round in roundsArray {
                if let score = round.scores?[self.id.uuidString] {
                    allScores.append(score)
                }
            }
            return allScores
        }
    }
    
    public var currentScore: Int32 {
        guard let game = activeGames.first else { return 0 }
        return game.roundsArray.last?.scores?[self.id.uuidString] ?? 0
    }
    
    public var totalGameScore: Int32 {
        scores.reduce(0, +)
    }
    
    public var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(gamesWon) / Double(gamesPlayed)
    }
    
    public var gamesArray: [Game] {
        let allObjects = games?.allObjects ?? []
        return (allObjects as? [Game])?.sorted { $0.startDate < $1.startDate } ?? []
    }
    
    public var activeGames: [Game] {
        let allObjects = games?.allObjects ?? []
        let activeGames = (allObjects as? [Game])?.filter { $0.isActive }.sorted { $0.startDate < $1.startDate } ?? []
        print("🎮 Player \(name) - Total games: \(allObjects.count), Active games: \(activeGames.count)")
        if !activeGames.isEmpty {
            print("🎮 Active game IDs: \(activeGames.map { $0.id })")
        }
        return activeGames
    }
    
    public var completedGames: [Game] {
        let allObjects = games?.allObjects ?? []
        return (allObjects as? [Game])?.filter { !$0.isActive }.sorted { $0.startDate < $1.startDate } ?? []
    }
    
    // MARK: - Statistics Management
    public func updateStatistics() {
        guard let allGames = games?.allObjects as? [Game] else { return }
        
        // Update games played
        gamesPlayed = Int32(allGames.count)
        
        // Update games won
        var wonGames = 0
        for game in allGames {
            if let lastRound = game.sortedRounds.last,
               let firstScore = lastRound.sortedScores.first,
               firstScore.player.id == self.id {
                wonGames += 1
            }
        }
        gamesWon = Int32(wonGames)
        
        // Update average position
        var totalPosition = 0
        var positionCount = 0
        
        for game in allGames {
            guard let lastRound = game.sortedRounds.last else { continue }
            
            for (index, score) in lastRound.sortedScores.enumerated() {
                if score.player.id == self.id {
                    totalPosition += index + 1
                    positionCount += 1
                    break
                }
            }
        }
        
        if positionCount > 0 {
            averagePosition = Double(totalPosition) / Double(positionCount)
        } else {
            averagePosition = 0
        }
        
        // Update total score
        totalScore = scores.reduce(0, +)
    }
    
    // MARK: - Game Management
    public func canJoinGame() -> Bool {
        activeGames.count < 3 // Limit concurrent games
    }
    
    public func canBeDeleted() -> Bool {
        activeGames.isEmpty
    }
    
    // Update totalScore calculation to use Int32 consistently
    public func updateTotalScore() {
        totalScore = scores.reduce(0, +)
    }
}

extension Player: Identifiable {} 