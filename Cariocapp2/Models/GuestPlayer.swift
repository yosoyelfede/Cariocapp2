import Foundation
import CoreData

struct GuestPlayer: Identifiable, Hashable, Codable {
    // MARK: - Properties
    let id: UUID
    let name: String
    
    // MARK: - Constants
    private static let maxNameLength = 30
    private static let minNameLength = 2
    private static let nameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9\\s'-]+$")
    
    // MARK: - Initialization
    init(id: UUID = UUID(), name: String) throws {
        self.id = id
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateName(trimmedName)
        self.name = trimmedName
    }
    
    // MARK: - Validation
    private static func validateName(_ name: String) throws {
        guard !name.isEmpty else {
            throw AppError.invalidPlayerState("Guest player name cannot be empty")
        }
        
        guard name.count >= minNameLength else {
            throw AppError.invalidPlayerState("Name must be at least \(minNameLength) characters")
        }
        
        guard name.count <= maxNameLength else {
            throw AppError.invalidPlayerState("Name must be at most \(maxNameLength) characters")
        }
        
        let range = NSRange(location: 0, length: name.utf16.count)
        guard nameRegex.firstMatch(in: name, range: range) != nil else {
            throw AppError.invalidPlayerState("Name can only contain letters, numbers, spaces, hyphens, and apostrophes")
        }
    }
    
    // MARK: - Equatable & Hashable
    static func == (lhs: GuestPlayer, rhs: GuestPlayer) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Conversion
    func toPlayer(context: NSManagedObjectContext) throws -> Player {
        let player = Player(context: context)
        player.id = UUID()
        player.name = name
        player.gamesPlayed = 0
        player.gamesWon = 0
        player.totalScore = 0
        player.averagePosition = 0
        player.isGuest = true
        player.createdAt = Date()
        
        // Validate the created player
        try player.validate()
        
        return player
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        try self.init(id: id, name: name)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
} 