import CoreData
import Foundation

protocol PlayerRepository {
    func createPlayer(name: String) throws -> Player
    func fetchPlayers(includeGuests: Bool) throws -> [Player]
    func updatePlayer(_ player: Player) throws
    func deletePlayer(_ player: Player) throws
    func findPlayer(byName name: String) throws -> Player?
    func batchDeleteInactivePlayers() throws
    func batchUpdateStatistics() throws
}

class CoreDataPlayerRepository: PlayerRepository, ObservableObject {
    @Published private(set) var context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
        print("🗄️ Repository initialized with context: \(context)")
    }
    
    func updateContext(_ newContext: NSManagedObjectContext) {
        self.context = newContext
        print("🗄️ Repository context updated to: \(newContext)")
    }
    
    func createPlayer(name: String) throws -> Player {
        // Validate name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.validationError("Player name cannot be empty")
        }
        
        // Check for duplicate names
        if try findPlayer(byName: trimmedName) != nil {
            throw AppError.validationError("A player with this name already exists")
        }
        
        print("🗄️ Creating player: \(trimmedName)")
        
        let player = Player(context: context)
        // Create a new UUID to avoid bridging issues
        let playerID = UUID()
        player.id = playerID
        player.name = trimmedName
        player.gamesPlayed = 0
        player.gamesWon = 0
        player.totalScore = 0
        player.averagePosition = 0
        player.isGuest = false
        player.createdAt = Date()
        
        try player.validate()
        try context.save()
        
        print("🗄️ Player created: \(player.name) with ID: \(playerID.uuidString), isGuest: \(player.isGuest)")
        return player
    }
    
    func fetchPlayers(includeGuests: Bool = false) throws -> [Player] {
        print("🗄️ Fetching players (includeGuests: \(includeGuests))")
        
        // Only clean up abandoned games when explicitly requested
        // This prevents unnecessary updates during regular fetches
        
        let request = NSFetchRequest<Player>(entityName: "Player")
        
        // Create predicate for guest filtering
        var predicates: [NSPredicate] = []
        
        // Add guest filtering if needed
        if !includeGuests {
            predicates.append(NSPredicate(format: "isGuest == false"))
        }
        
        // Combine predicates if we have any
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Player.name, ascending: true)]
        
        let players = try context.fetch(request)
        print("🗄️ Fetched \(players.count) \(includeGuests ? "total" : "non-guest") players")
        
        // Additional validation to ensure we only return valid players
        let validPlayers = players.filter { player in
            !player.isDeleted && player.managedObjectContext != nil
        }
        
        print("🗄️ Found \(validPlayers.count) valid players after filtering")
        return validPlayers
    }
    
    func cleanupAbandonedGames() throws {
        print("🗄️ Starting abandoned games cleanup")
        let request = NSFetchRequest<Game>(entityName: "Game")
        request.predicate = NSPredicate(format: "isActive == true AND rounds.@count == 1")
        
        let abandonedGames = try context.fetch(request)
        print("🗄️ Found \(abandonedGames.count) abandoned games")
        
        for game in abandonedGames {
            print("🗄️ Cleaning up abandoned game: \(game.id)")
            game.cleanup()
            context.delete(game)
        }
        
        if !abandonedGames.isEmpty {
            try context.save()
            print("🗄️ Cleanup complete")
        }
    }
    
    func updatePlayer(_ player: Player) throws {
        print("🗄️ Updating player: \(player.name)")
        
        try player.validate()
        
        // Check for duplicate names if name changed
        if player.name != player.name.trimmingCharacters(in: .whitespacesAndNewlines) {
            let trimmedName = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingPlayer = try findPlayer(byName: trimmedName), existingPlayer != player {
                throw AppError.validationError("A player with this name already exists")
            }
            player.name = trimmedName
        }
        
        if context.hasChanges {
            try context.save()
            print("🗄️ Player updated successfully")
        }
    }
    
    func deletePlayer(_ player: Player) throws {
        print("🗄️ Deleting player: \(player.name)")
        
        // Check if player can be deleted
        if !player.activeGames.isEmpty {
            throw AppError.invalidPlayerState("Cannot delete player with active games")
        }
        
        // Remove player from any games they were part of first
        let gameRequest = NSFetchRequest<Game>(entityName: "Game")
        if let games = try? context.fetch(gameRequest) {
            for game in games {
                if let players = game.players as? Set<Player>, players.contains(player) {
                    var updatedPlayers = players
                    updatedPlayers.remove(player)
                    game.players = updatedPlayers as NSSet
                }
            }
        }
        
        // Delete the player
        context.delete(player)
        
        // Force a save to ensure deletion is persisted
        try context.save()
        
        // Refresh the context to ensure deletion is reflected
        context.refreshAllObjects()
        
        print("🗄️ Player deleted successfully")
    }
    
    func findPlayer(byName name: String) throws -> Player? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let request = NSFetchRequest<Player>(entityName: "Player")
        request.predicate = NSPredicate(format: "name ==[c] %@", trimmedName)
        request.fetchLimit = 1
        
        let player = try context.fetch(request).first
        print("🗄️ Find player by name '\(trimmedName)': \(player != nil ? "found" : "not found")")
        return player
    }
    
    // MARK: - Batch Operations
    
    func batchDeleteInactivePlayers() throws {
        print("🗄️ Cleaning up abandoned games")
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Game")
        request.predicate = NSPredicate(format: "isActive == true AND rounds.@count == 1")
        
        let games = try context.fetch(request) as? [Game] ?? []
        print("🗄️ Found \(games.count) abandoned games")
        
        for game in games {
            print("🗄️ Cleaning up abandoned game: \(game.id)")
            game.cleanup()
            context.delete(game)
        }
        
        if !games.isEmpty {
            try context.save()
            print("🗄️ Cleanup complete")
        }
    }
    
    func batchUpdateStatistics() throws {
        print("🗄️ Starting batch statistics update")
        
        let request = NSFetchRequest<Player>(entityName: "Player")
        let players = try context.fetch(request)
        
        // Use batch update for resetting statistics
        let batchUpdate = NSBatchUpdateRequest(entityName: "Player")
        batchUpdate.propertiesToUpdate = [
            "gamesPlayed": 0,
            "gamesWon": 0,
            "totalScore": 0,
            "averagePosition": 0.0
        ]
        batchUpdate.resultType = .updatedObjectIDsResultType
        
        let result = try context.execute(batchUpdate) as? NSBatchUpdateResult
        let changes: [AnyHashable: Any] = [
            NSUpdatedObjectIDsKey: result?.result as? [NSManagedObjectID] ?? []
        ]
        
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        
        // Update statistics for each player
        for player in players {
            player.updateStatistics()
        }
        
        try context.save()
        print("🗄️ Batch statistics update completed")
    }
} 