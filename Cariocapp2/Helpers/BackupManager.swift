import CoreData
import Foundation
import Compression
import UIKit

enum BackupError: LocalizedError {
    case encodingError(String)
    case decodingError(String)
    case fileError(String)
    case invalidData
    case invalidVersion(Int)
    case incompatibleVersion(current: Int, backup: Int)
    case validationError(String)
    case noBackupFound
    case exportFailed
    case importFailed
    
    var errorDescription: String? {
        switch self {
        case .encodingError(let message): return "Failed to encode data: \(message)"
        case .decodingError(let message): return "Failed to decode backup: \(message)"
        case .fileError(let message): return "File operation failed: \(message)"
        case .invalidData: return "The backup data is invalid or corrupted"
        case .invalidVersion(let version): return "Invalid backup version: \(version)"
        case .incompatibleVersion(let current, let backup): 
            return "Incompatible backup version. Current: \(current), Backup: \(backup)"
        case .validationError(let message): return "Validation failed: \(message)"
        case .noBackupFound: return "No backup found"
        case .exportFailed: return "Export failed"
        case .importFailed: return "Import failed"
        }
    }
}

/// Type-safe wrapper for game scores
@propertyWrapper
struct GameScores: Codable {
    private var dictionary: [String: Int32]
    
    var wrappedValue: [String: Int32] {
        get { dictionary }
        set { dictionary = newValue }
    }
    
    init(wrappedValue: [String: Int32]) {
        self.dictionary = wrappedValue
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        dictionary = try container.decode([String: Int32].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dictionary)
    }
    
    var projectedValue: [String: Int32] {
        get { dictionary }
        set { dictionary = newValue }
    }
}

class PlayerBackup: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    
    let id: UUID
    let name: String
    let gamesPlayed: Int32
    let gamesWon: Int32
    let averagePosition: Double
    let totalScore: Int32
    
    init(id: UUID, name: String, gamesPlayed: Int32, gamesWon: Int32, averagePosition: Double, totalScore: Int32) {
        self.id = id
        self.name = name
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.averagePosition = averagePosition
        self.totalScore = totalScore
        super.init()
    }
    
    required init?(coder: NSCoder) {
        guard let idString = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let id = UUID(uuidString: idString) else {
            return nil
        }
        
        guard let name = coder.decodeObject(of: NSString.self, forKey: "name") as String? else {
            return nil
        }
        
        self.id = id
        self.name = name
        self.gamesPlayed = coder.decodeInt32(forKey: "gamesPlayed")
        self.gamesWon = coder.decodeInt32(forKey: "gamesWon")
        self.averagePosition = coder.decodeDouble(forKey: "averagePosition")
        self.totalScore = coder.decodeInt32(forKey: "totalScore")
        
        super.init()
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id.uuidString as NSString, forKey: "id")
        coder.encode(name as NSString, forKey: "name")
        coder.encode(gamesPlayed, forKey: "gamesPlayed")
        coder.encode(gamesWon, forKey: "gamesWon")
        coder.encode(averagePosition, forKey: "averagePosition")
        coder.encode(totalScore, forKey: "totalScore")
    }
}

class RoundBackup: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    
    let id: UUID
    let number: Int16
    let dealerIndex: Int16
    let isCompleted: Bool
    let isSkipped: Bool
    let scores: [String: Int32]
    
    init(id: UUID, number: Int16, dealerIndex: Int16, isCompleted: Bool, isSkipped: Bool, scores: [String: Int32]) {
        self.id = id
        self.number = number
        self.dealerIndex = dealerIndex
        self.isCompleted = isCompleted
        self.isSkipped = isSkipped
        self.scores = scores
        super.init()
    }
    
    required init?(coder: NSCoder) {
        guard let idString = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let id = UUID(uuidString: idString) else {
            return nil
        }
        
        self.id = id
        self.number = Int16(coder.decodeInt32(forKey: "number"))
        self.dealerIndex = Int16(coder.decodeInt32(forKey: "dealerIndex"))
        self.isCompleted = coder.decodeBool(forKey: "isCompleted")
        self.isSkipped = coder.decodeBool(forKey: "isSkipped")
        
        guard let scoresDict = coder.decodeObject(of: NSDictionary.self, forKey: "scores") as? [String: Int32] else {
            self.scores = [:]
            super.init()
            return
        }
        
        self.scores = scoresDict
        super.init()
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id.uuidString as NSString, forKey: "id")
        coder.encode(Int32(number), forKey: "number")
        coder.encode(Int32(dealerIndex), forKey: "dealerIndex")
        coder.encode(isCompleted, forKey: "isCompleted")
        coder.encode(isSkipped, forKey: "isSkipped")
        coder.encode(scores as NSDictionary, forKey: "scores")
    }
}

class GameBackup: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true
    
    let id: UUID
    let startDate: Date
    let currentRound: Int16
    let dealerIndex: Int16
    let isActive: Bool
    let players: [PlayerBackup]
    let rounds: [RoundBackup]
    
    init(id: UUID, startDate: Date, currentRound: Int16, dealerIndex: Int16, isActive: Bool, players: [PlayerBackup], rounds: [RoundBackup]) {
        self.id = id
        self.startDate = startDate
        self.currentRound = currentRound
        self.dealerIndex = dealerIndex
        self.isActive = isActive
        self.players = players
        self.rounds = rounds
        super.init()
    }
    
    required init?(coder: NSCoder) {
        guard let idString = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let id = UUID(uuidString: idString) else {
            return nil
        }
        
        guard let startDate = coder.decodeObject(of: NSDate.self, forKey: "startDate") as Date? else {
            return nil
        }
        
        guard let players = coder.decodeObject(of: [NSArray.self, PlayerBackup.self], forKey: "players") as? [PlayerBackup],
              let rounds = coder.decodeObject(of: [NSArray.self, RoundBackup.self], forKey: "rounds") as? [RoundBackup] else {
            return nil
        }
        
        self.id = id
        self.startDate = startDate
        self.currentRound = Int16(coder.decodeInt32(forKey: "currentRound"))
        self.dealerIndex = Int16(coder.decodeInt32(forKey: "dealerIndex"))
        self.isActive = coder.decodeBool(forKey: "isActive")
        self.players = players
        self.rounds = rounds
        
        super.init()
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id.uuidString as NSString, forKey: "id")
        coder.encode(startDate, forKey: "startDate")
        coder.encode(Int32(currentRound), forKey: "currentRound")
        coder.encode(Int32(dealerIndex), forKey: "dealerIndex")
        coder.encode(isActive, forKey: "isActive")
        coder.encode(players as NSArray, forKey: "players")
        coder.encode(rounds as NSArray, forKey: "rounds")
    }
}

@globalActor
actor BackupActor {
    static let shared = BackupActor()
    private init() {}
}

@BackupActor
final class BackupManager {
    // MARK: - Properties
    static let shared = BackupManager()
    private let fileManager: FileManager
    private let backupQueue: OperationQueue
    private let context: NSManagedObjectContext
    
    // MARK: - Initialization
    private init() {
        self.fileManager = .default
        self.backupQueue = OperationQueue()
        backupQueue.maxConcurrentOperationCount = 1
        backupQueue.qualityOfService = .utility
        
        // Create background context
        let context = PersistenceController.shared.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        self.context = context
        
        setupBackupDirectory()
    }
    
    // MARK: - Backup Management
    func createBackup() async throws {
        // Create backup in background
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            backupQueue.addOperation { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: BackupError.exportFailed)
                    return
                }
                
                Task { @BackupActor in
                    do {
                        // 1. Export data
                        let data = try await self.exportData()
                        
                        // 2. Create backup file
                        let backupURL = try await self.createBackupFile()
                        
                        // 3. Write data
                        try data.write(to: backupURL)
                        
                        // 4. Cleanup old backups
                        try await self.cleanupOldBackups()
                        
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    func restoreFromLatestBackup() async throws {
        // Find latest backup
        guard let backupURL = try findLatestBackup() else {
            throw BackupError.noBackupFound
        }
        
        // Read backup data
        let data = try Data(contentsOf: backupURL)
        
        // Import data
        try await importData(data)
    }
    
    // MARK: - Helper Methods
    private func setupBackupDirectory() {
        do {
            let backupURL = try getBackupDirectoryURL()
            try fileManager.createDirectory(
                at: backupURL,
                withIntermediateDirectories: true
            )
        } catch {
            print("Failed to create backup directory: \(error)")
        }
    }
    
    private func getBackupDirectoryURL() throws -> URL {
        try fileManager
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }
    
    @BackupActor
    private func createBackupFile() async throws -> URL {
        let backupURL = try getBackupDirectoryURL()
        let fileName = "backup_\(Date().timeIntervalSince1970).dat"
        return backupURL.appendingPathComponent(fileName)
    }
    
    private func findLatestBackup() throws -> URL? {
        let backupURL = try getBackupDirectoryURL()
        let contents = try fileManager.contentsOfDirectory(
            at: backupURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        return contents
            .filter { $0.pathExtension == "dat" }
            .sorted { (url1, url2) -> Bool in
                let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate
                let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate
                return date1 ?? Date.distantPast > date2 ?? Date.distantPast
            }
            .first
    }
    
    private func cleanupOldBackups() async throws {
        let backupURL = try getBackupDirectoryURL()
        let contents = try fileManager.contentsOfDirectory(
            at: backupURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        let maxBackups = 5
        let sortedBackups = contents
            .filter { $0.pathExtension == "dat" }
            .sorted { (url1, url2) -> Bool in
                let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate
                let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate
                return date1 ?? Date.distantPast > date2 ?? Date.distantPast
            }
        
        if sortedBackups.count > maxBackups {
            for backup in sortedBackups[maxBackups...] {
                try fileManager.removeItem(at: backup)
            }
        }
    }
    
    // MARK: - Data Export/Import
    private func exportData() async throws -> Data {
        // Fetch all games
        let fetchRequest: NSFetchRequest<Game> = Game.fetchRequest()
        let games = try context.fetch(fetchRequest)
        
        // Create backup objects
        let backups = try games.map { game -> GameBackup in
            let playerBackups = try game.playersArray.map { player -> PlayerBackup in
                PlayerBackup(
                    id: player.id,
                    name: player.name,
                    gamesPlayed: player.gamesPlayed,
                    gamesWon: player.gamesWon,
                    averagePosition: player.averagePosition,
                    totalScore: player.totalScore
                )
            }
            
            let roundBackups = try game.roundsArray.map { round -> RoundBackup in
                round.toBackup()
            }
            
            return GameBackup(
                id: game.id,
                startDate: game.startDate,
                currentRound: game.currentRound,
                dealerIndex: game.dealerIndex,
                isActive: game.isActive,
                players: playerBackups,
                rounds: roundBackups
            )
        }
        
        // Archive data
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: backups as NSArray,
            requiringSecureCoding: true
        )
        
        return data
    }
    
    private func importData(_ data: Data) async throws {
        // Unarchive data
        guard let backups = try NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, GameBackup.self, PlayerBackup.self, RoundBackup.self, NSString.self, NSNumber.self, NSDictionary.self, NSDate.self],
            from: data
        ) as? [GameBackup] else {
            throw BackupError.decodingError("Failed to decode backup data")
        }
        
        // Delete existing data
        try deleteAllGames()
        
        // Restore games
        for backup in backups {
            try await restoreGame(backup)
        }
        
        // Save changes
        if context.hasChanges {
            try context.save()
        }
    }
    
    private func deleteAllGames() throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Game.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try context.execute(deleteRequest)
    }
    
    private func restoreGame(_ backup: GameBackup) async throws {
        // Create game
        let game = Game(context: context)
        game.id = backup.id
        game.startDate = backup.startDate
        game.currentRound = backup.currentRound
        game.dealerIndex = backup.dealerIndex
        game.isActive = backup.isActive
        
        // Restore players
        var players = Set<Player>()
        for playerBackup in backup.players {
            let player = Player(context: context)
            player.id = playerBackup.id
            player.name = playerBackup.name
            player.gamesPlayed = playerBackup.gamesPlayed
            player.gamesWon = playerBackup.gamesWon
            player.averagePosition = playerBackup.averagePosition
            player.totalScore = playerBackup.totalScore
            players.insert(player)
        }
        game.players = players as NSSet
        
        // Restore rounds
        var rounds = Set<Round>()
        for roundBackup in backup.rounds {
            let round = Round(context: context)
            round.id = roundBackup.id
            round.number = roundBackup.number
            round.dealerIndex = roundBackup.dealerIndex
            round.isCompleted = roundBackup.isCompleted
            round.isSkipped = roundBackup.isSkipped
            round.scores = roundBackup.scores
            rounds.insert(round)
        }
        game.rounds = rounds as NSSet
    }
}

// MARK: - Supporting Types

struct BackupMetadata: Codable {
    let timestamp: Date
    let hash: String
    let version: String
    let playerCount: Int
    let gameCount: Int
}

extension Round {
    func toBackup() -> RoundBackup {
        return RoundBackup(
            id: self.id,
            number: self.number,
            dealerIndex: self.dealerIndex,
            isCompleted: self.isCompleted,
            isSkipped: self.isSkipped,
            scores: self.scores ?? [:]
        )
    }
}

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
} 