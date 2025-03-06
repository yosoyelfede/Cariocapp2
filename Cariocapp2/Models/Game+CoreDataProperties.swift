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
    @NSManaged public var playerSnapshots: NSArray?
    
    public var playerSnapshotsArray: [PlayerSnapshot] {
        get {
            return playerSnapshots?.map { $0 as! PlayerSnapshot } ?? []
        }
        set {
            playerSnapshots = newValue as NSArray
        }
    }
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        startDate = Date()
        currentRound = 1
        dealerIndex = 0
        isActive = true
        playerSnapshotsArray = []
    }
    
    // MARK: - Public Properties
    public var playersArray: [Player] {
        let allObjects = players?.allObjects ?? []
        return (allObjects as? [Player])?.sorted { $0.name < $1.name } ?? []
    }
    
    public var roundsArray: [Round] {
        let allObjects = rounds?.allObjects ?? []
        return (allObjects as? [Round])?.sorted { $0.number < $1.number } ?? []
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
        print("🎯 [isComplete] Round \(currentRound): checking completion")
        
        let allRounds = roundsArray
        let round12 = allRounds.first(where: { $0.number == 12 })
        
        if let round12 = round12 {
            print("🎯 [isComplete] Round 12: completed=\(round12.isCompleted)")
            guard round12.isCompleted && !round12.isSkipped else {
                return false
            }
        } else {
            return false
        }
        
        // Get all non-skipped rounds
        let nonSkippedRounds = allRounds.filter { !$0.isSkipped }
        
        // Verify required rounds (1-8)
        let requiredRoundNumbers: Set<Int16> = [1, 2, 3, 4, 5, 6, 7, 8]
        let completedRequiredRounds = nonSkippedRounds.filter { round in
            requiredRoundNumbers.contains(round.number) && round.isCompleted
        }
        
        guard completedRequiredRounds.count == requiredRoundNumbers.count else {
            return false
        }
        
        // Check optional rounds (9-11)
        let optionalRoundNumbers: Set<Int16> = [9, 10, 11]
        let optionalRounds = allRounds.filter { optionalRoundNumbers.contains($0.number) }
        let allOptionalHandled = optionalRounds.allSatisfy({ $0.isSkipped || $0.isCompleted })
        
        guard allOptionalHandled else {
            return false
        }
        
        print("🎯 [isComplete] Game is complete!")
        return true
    }
    
    public var currentRoundDescription: String {
        guard currentRound > 0 && currentRound <= maxRounds else { return "Invalid Round" }
        return roundsArray.first { $0.number == currentRound }?.description ?? "Unknown Round"
    }
    
    // MARK: - Validation
    public func validate() throws {
        // Validate ID
        guard id != UUID.init() else {
            throw AppError.invalidGameState("Game ID is invalid")
        }
        
        // Validate players
        guard let players = players else {
            throw AppError.invalidGameState("Game has no players")
        }
        
        guard players.count >= 2 && players.count <= 4 else {
            throw AppError.invalidGameState("Game must have between 2 and 4 players")
        }
        
        // Validate rounds
        guard let rounds = rounds else {
            throw AppError.invalidGameState("Game has no rounds")
        }
        
        let roundsArray = rounds.allObjects as? [Round] ?? []
        guard roundsArray.count <= 12 else {
            throw AppError.invalidGameState("Game cannot have more than 12 rounds")
        }
        
        // Validate round numbers
        let roundNumbers = roundsArray.map { $0.number }
        guard Set(roundNumbers).count == roundNumbers.count else {
            throw AppError.invalidGameState("Duplicate round numbers found")
        }
        
        // Validate round sequence
        let sortedRoundNumbers = roundNumbers.sorted()
        guard sortedRoundNumbers == Array((1...roundNumbers.count).map { Int16($0) }) else {
            throw AppError.invalidGameState("Invalid round sequence")
        }
        
        // Validate start date
        guard startDate <= Date() else {
            throw AppError.invalidGameState("Start date cannot be in the future")
        }
        
        // If game is not active, validate end date
        if !isActive {
            guard let endDate = endDate else {
                throw AppError.invalidGameState("Inactive game must have an end date")
            }
            guard endDate >= startDate else {
                throw AppError.invalidGameState("End date must be after start date")
            }
            guard endDate <= Date() else {
                throw AppError.invalidGameState("End date cannot be in the future")
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
        
        // Only update if the game is currently active
        if isActive {
            isActive = false
            endDate = Date()
            
            // Create snapshot if needed
            if playerSnapshotsArray.isEmpty {
                createSnapshot()
            }
            
            print("🎮 Game \(id) completed")
        }
    }
    
    public func createSnapshot() {
        print("📸 Creating game snapshot for game \(id)")
        
        // Create a dictionary to map player IDs to their total scores
        var playerScores: [String: Int32] = [:]
        
        // Calculate total scores for each player
        for player in playersArray {
            var totalScore: Int32 = 0
            
            // Sum up scores from all rounds
            for round in sortedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    totalScore += score
                }
            }
            
            playerScores[player.id.uuidString] = totalScore
        }
        
        // Sort players by score (lowest first for this game - lower is better)
        let sortedPlayers = playersArray.sorted { 
            (playerScores[$0.id.uuidString] ?? 0) < (playerScores[$1.id.uuidString] ?? 0)
        }
        
        // Create snapshots with positions
        let snapshots = sortedPlayers.enumerated().map { index, player in
            PlayerSnapshot(
                id: player.id,
                name: player.name,
                score: Int(playerScores[player.id.uuidString] ?? 0),
                position: index + 1
            )
        }
        
        print("📸 Created \(snapshots.count) player snapshots:")
        for snapshot in snapshots {
            print("📸 Player: \(snapshot.name), Position: \(snapshot.position), Score: \(snapshot.score)")
        }
        
        self.playerSnapshotsArray = snapshots
    }
    
    // MARK: - Game Management
    public func addPlayer(_ player: Player) throws {
        guard isActive else {
            throw AppError.invalidGameState("Cannot add player to inactive game")
        }
        
        guard !playersArray.contains(where: { $0.id == player.id }) else {
            throw AppError.invalidGameState("Player is already in the game")
        }
        
        guard player.canJoinGame() else {
            throw AppError.invalidGameState("Player cannot join more games")
        }
        
        var updatedPlayers = players as? Set<Player> ?? Set<Player>()
        updatedPlayers.insert(player)
        players = updatedPlayers as NSSet
    }
    
    public func removePlayer(_ player: Player) throws {
        guard isActive else {
            throw AppError.invalidGameState("Cannot remove player from inactive game")
        }
        
        guard playersArray.contains(where: { $0.id == player.id }) else {
            throw AppError.invalidGameState("Player is not in the game")
        }
        
        var updatedPlayers = players as? Set<Player> ?? Set<Player>()
        updatedPlayers.remove(player)
        players = updatedPlayers as NSSet
    }
    
    public func canStart() -> Bool {
        guard let players = players else { return false }
        return players.count >= 2 && players.count <= 4
    }
    
    public func takeSnapshot() {
        let snapshots = playersArray.map { player in
            PlayerSnapshot(
                id: player.id,
                name: player.name,
                score: Int(player.totalScore),
                position: 0
            )
        }
        playerSnapshotsArray = snapshots
    }
}

extension Game: Identifiable {} 