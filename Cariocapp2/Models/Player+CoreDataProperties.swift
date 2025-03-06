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
        print("🔄 Starting statistics update for player \(name)")
        
        // IMPORTANT: Reset all statistics to zero
        gamesPlayed = 0
        gamesWon = 0
        totalScore = 0
        averagePosition = 0
        
        // Get all completed games
        let allCompletedGames = self.completedGames
        print("🔄 Found \(allCompletedGames.count) completed games for player \(name)")
        
        // Track processed games to avoid duplicates
        var processedGameIDs = Set<UUID>()
        var totalPositions = 0
        var totalGamesWithPositions = 0
        
        // Process each completed game
        for game in allCompletedGames {
            // Skip if we've already processed this game
            if processedGameIDs.contains(game.id) {
                print("🔄 Skipping already processed game \(game.id)")
                continue
            }
            
            // Skip games without snapshots
            if game.playerSnapshotsArray.isEmpty {
                print("🔄 Skipping game \(game.id) - no player snapshots")
                continue
            }
            
            // Find this player's snapshot in the game
            if let snapshot = game.playerSnapshotsArray.first(where: { $0.id == self.id }) {
                // Increment games played
                gamesPlayed += 1
                
                // Check if player won
                if snapshot.position == 1 {
                    gamesWon += 1
                    print("🔄 Player \(name) won game \(game.id)")
                }
                
                // Add to total score
                totalScore += Int32(snapshot.score)
                
                // Track position for average calculation
                totalPositions += snapshot.position
                totalGamesWithPositions += 1
                
                print("🔄 Processed game \(game.id) - position: \(snapshot.position), score: \(snapshot.score)")
            } else {
                print("🔄 Skipping game \(game.id) - player has no snapshot")
            }
            
            // Mark this game as processed
            processedGameIDs.insert(game.id)
        }
        
        // Calculate average position
        if totalGamesWithPositions > 0 {
            averagePosition = Double(totalPositions) / Double(totalGamesWithPositions)
        }
        
        print("🔄 Statistics updated for \(name): played=\(gamesPlayed), won=\(gamesWon), avg pos=\(averagePosition), score=\(totalScore)")
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