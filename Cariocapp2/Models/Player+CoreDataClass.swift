import Foundation
import CoreData

@objc(Player)
public class Player: NSManagedObject {
    // MARK: - Constants
    private static let minNameLength = 2
    private static let maxNameLength = 30
    private static let nameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9\\s'-]+$")
    
    // MARK: - Validation Errors
    enum ValidationError: LocalizedError {
        case invalidName(String)
        case emptyName
        case nameTooShort(String)
        case nameTooLong(String)
        case invalidNameFormat(String)
        case duplicatePlayer(String)
        case invalidStatistics
        
        var errorDescription: String? {
            switch self {
            case .invalidName(let name):
                return "Invalid player name: \(name)"
            case .emptyName:
                return "Player name cannot be empty"
            case .nameTooShort(let name):
                return "Name '\(name)' is too short (minimum \(Player.minNameLength) characters)"
            case .nameTooLong(let name):
                return "Name '\(name)' is too long (maximum \(Player.maxNameLength) characters)"
            case .invalidNameFormat(let name):
                return "Name '\(name)' contains invalid characters"
            case .duplicatePlayer(let name):
                return "Player with name '\(name)' already exists"
            case .invalidStatistics:
                return "Invalid player statistics"
            }
        }
    }
    
    // MARK: - Factory Methods
    static func createPlayer(name: String, context: NSManagedObjectContext) throws -> Player {
        // Validate name
        try validatePlayerName(name, context: context)
        
        // Create player
        let player = Player(context: context)
        player.id = UUID()
        player.name = name
        player.gamesPlayed = 0
        player.gamesWon = 0
        player.totalScore = 0
        player.averagePosition = 0
        player.isGuest = false
        player.createdAt = Date()
        
        // Verify state
        try player.validateState()
        
        return player
    }
    
    // MARK: - Validation
    private static func validatePlayerName(_ name: String, context: NSManagedObjectContext) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for empty name
        guard !trimmedName.isEmpty else {
            throw ValidationError.emptyName
        }
        
        // Check length
        guard trimmedName.count >= minNameLength else {
            throw ValidationError.nameTooShort(trimmedName)
        }
        
        guard trimmedName.count <= maxNameLength else {
            throw ValidationError.nameTooLong(trimmedName)
        }
        
        // Check format
        let range = NSRange(location: 0, length: trimmedName.utf16.count)
        guard nameRegex.firstMatch(in: trimmedName, range: range) != nil else {
            throw ValidationError.invalidNameFormat(trimmedName)
        }
        
        // Check for duplicates
        let request = NSFetchRequest<Player>(entityName: "Player")
        request.predicate = NSPredicate(format: "name ==[c] %@", trimmedName)
        request.fetchLimit = 1
        
        let count = try context.count(for: request)
        if count > 0 {
            throw ValidationError.duplicatePlayer(trimmedName)
        }
    }
    
    func validateState() throws {
        // Validate ID
        guard id != UUID.init() else {
            throw ValidationError.invalidName("Player ID is invalid")
        }
        
        // Validate name
        guard !name.isEmpty else {
            throw ValidationError.emptyName
        }
        
        guard name.count >= Self.minNameLength else {
            throw ValidationError.nameTooShort(name)
        }
        
        guard name.count <= Self.maxNameLength else {
            throw ValidationError.nameTooLong(name)
        }
        
        // Check name format
        let range = NSRange(location: 0, length: name.utf16.count)
        guard Self.nameRegex.firstMatch(in: name, options: [], range: range) != nil else {
            throw ValidationError.invalidNameFormat(name)
        }
        
        // Check for duplicates
        if let context = managedObjectContext {
            let request = NSFetchRequest<Player>(entityName: "Player")
            request.predicate = NSPredicate(format: "name == %@ AND id != %@", name, id as CVarArg)
            if let count = try? context.count(for: request), count > 0 {
                throw ValidationError.duplicatePlayer(name)
            }
        }
        
        // Validate statistics
        guard gamesPlayed >= 0,
              gamesWon >= 0,
              gamesWon <= gamesPlayed,
              totalScore >= 0,
              averagePosition >= 0 else {
            throw ValidationError.invalidStatistics
        }
    }
    
    // MARK: - Statistics
    func updateStatistics(gameWon: Bool, finalPosition: Int, score: Int32) throws {
        guard finalPosition > 0 else {
            throw ValidationError.invalidStatistics
        }
        
        gamesPlayed += 1
        if gameWon { gamesWon += 1 }
        totalScore += score
        
        // Update average position using weighted average
        let newAvgPosition = (averagePosition * Double(gamesPlayed - 1) + Double(finalPosition)) / Double(gamesPlayed)
        averagePosition = newAvgPosition
        
        try validateState()
    }
    
    // MARK: - Cleanup
    func cleanup() {
        print("🧹 Starting cleanup for player: \(name)")
        
        // Remove game relationships
        if let games = games {
            print("🧹 Cleaning up \(games.count) game relationships")
            self.games = nil
            games.forEach { game in
                if let game = game as? Game {
                    // Remove this player from the game's players set
                    var updatedPlayers = game.players as? Set<Player> ?? Set<Player>()
                    updatedPlayers.remove(self)
                    game.players = updatedPlayers as NSSet
                }
            }
        }
        
        // Mark as guest to ensure it's filtered out
        isGuest = true
        
        print("🧹 Cleanup complete for player: \(name)")
    }
} 
