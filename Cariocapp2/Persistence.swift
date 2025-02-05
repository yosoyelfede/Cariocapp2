//
//  Persistence.swift
//  Cariocapp2
//
//  Created by Federico Antunovic on 29-01-25.
//

import CoreData
import Foundation
import SwiftUI

/// Controller for managing Core Data persistence
final class PersistenceController {
    // MARK: - Constants
    private struct StoreVersion {
        static let current = 1
        static let minimumCompatible = 1
        static let modelName = "Cariocapp2"
    }
    
    private struct Configuration {
        static let maxRetryAttempts = 3
        static let retryDelay: TimeInterval = 0.5
        static let maxHistoryItems = 100
        static let backupBeforeMigration = true
    }
    
    // MARK: - Errors
    enum PersistenceError: LocalizedError {
        case storeLoadFailed(Error)
        case migrationFailed(Error)
        case incompatibleVersion(current: Int, required: Int)
        case dataCorruption(String)
        case recoveryFailed(Error)
        case backupFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .storeLoadFailed(let error):
                return "Failed to load persistent store: \(error.localizedDescription)"
            case .migrationFailed(let error):
                return "Migration failed: \(error.localizedDescription)"
            case .incompatibleVersion(let current, let required):
                return "Incompatible store version. Current: \(current), Required: \(required)"
            case .dataCorruption(let message):
                return "Data corruption detected: \(message)"
            case .recoveryFailed(let error):
                return "Recovery failed: \(error.localizedDescription)"
            case .backupFailed(let error):
                return "Backup failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Shared Instance
    static let shared = PersistenceController()
    
    // MARK: - Preview Support
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Configure view context
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.automaticallyMergesChangesFromParent = true
        
        // Set up preview store URL
        if let description = result.container.persistentStoreDescriptions.first {
            let url = URL.temporaryDirectory.appendingPathComponent("preview_store.sqlite")
            description.url = url
            description.type = NSInMemoryStoreType
            
            // Ensure store is recreated for preview
            try? FileManager.default.removeItem(at: url)
        }
        
        do {
            // Create real players for preview
            let fede = Player(context: viewContext)
            fede.id = UUID()
            fede.name = "Fede"
            fede.gamesPlayed = 0
            fede.gamesWon = 0
            fede.createdAt = Date()
            fede.averagePosition = 0
            fede.totalScore = 0
            fede.isGuest = false
            
            let mari = Player(context: viewContext)
            mari.id = UUID()
            mari.name = "Mari"
            mari.gamesPlayed = 0
            mari.gamesWon = 0
            mari.createdAt = Date()
            mari.averagePosition = 0
            mari.totalScore = 0
            mari.isGuest = false
            
            try viewContext.save()
            print("🎮 Preview data created successfully")
        } catch {
            let nsError = error as NSError
            print("❌ Failed to create preview data: \(error.localizedDescription)")
            print("❌ Detailed error: \(nsError.userInfo)")
            
            // Try to recover
            viewContext.rollback()
            
            // Reset the store
            if let storeURL = result.container.persistentStoreDescriptions.first?.url {
                do {
                    try result.container.persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: NSInMemoryStoreType, options: nil)
                    try result.container.persistentStoreCoordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: storeURL, options: nil)
                    print("🎮 Successfully recreated preview store")
                } catch {
                    print("❌ Failed to recreate preview store: \(error)")
                }
            }
        }
        
        return result
    }()
    
    // MARK: - Properties
    let container: NSPersistentContainer
    private var loadError: Error?
    
    // MARK: - Initialization
    init(inMemory: Bool = false) {
        print("🎮 Initializing PersistenceController (inMemory: \(inMemory))")
        container = NSPersistentContainer(name: "Cariocapp2")
        
        // Configure store description
        if let description = container.persistentStoreDescriptions.first {
            // Set store type and options
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            
            if inMemory {
                let url = URL.temporaryDirectory.appendingPathComponent("temp_store.sqlite")
                description.url = url
                // Ensure store is recreated
                try? FileManager.default.removeItem(at: url)
            }
            
            // Configure automatic migration and merge policies
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            
            // Set merge policies
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            container.viewContext.automaticallyMergesChangesFromParent = true
            
            // Configure SQLite options for persistent store
            if !inMemory {
                description.setOption(["journal_mode": "WAL"] as NSDictionary,
                                    forKey: NSSQLitePragmasOption)
            }
            
            // Configure notifications and history tracking
            description.setOption(true as NSNumber,
                                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.setOption(true as NSNumber,
                                forKey: NSPersistentHistoryTrackingKey)
            
            print("🎮 Store configuration complete")
        }
        
        // Load store with retry
        var loadError: Error?
        let group = DispatchGroup()
        group.enter()
        
        container.loadPersistentStores { description, error in
            defer { group.leave() }
            if let error = error {
                loadError = error
                print("Failed to load Core Data store: \(error)")
                print("Detailed error: \(error as NSError).userInfo")
            } else {
                print("Successfully loaded Core Data store")
            }
        }
        
        group.wait()
        
        if let error = loadError {
            // Try to recover from load error
            do {
                try recoverFromLoadError(error)
            } catch {
                print("Unrecoverable store error: \(error)")
                print("Detailed error: \(error as NSError).userInfo")
            }
        }
        
        setupNotificationHandling()
    }
    
    // MARK: - Notification Handling
    private func setupNotificationHandling() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(managedObjectContextObjectsDidChange),
            name: NSManagedObjectContext.didChangeObjectsNotification,
            object: container.viewContext
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(managedObjectContextDidSave),
            name: NSManagedObjectContext.didSaveObjectsNotification,
            object: nil
        )
    }
    
    @objc
    private func managedObjectContextObjectsDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
        let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? []
        
        // Handle changes
        handleChangedObjects(inserted: insertedObjects, updated: updatedObjects, deleted: deletedObjects)
    }
    
    @objc
    private func managedObjectContextDidSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext,
              context !== container.viewContext else { return }
        
        container.viewContext.perform {
            self.container.viewContext.mergeChanges(fromContextDidSave: notification)
        }
    }
    
    private func handleChangedObjects(
        inserted: Set<NSManagedObject>,
        updated: Set<NSManagedObject>,
        deleted: Set<NSManagedObject>
    ) {
        // Handle inserted objects
        for object in inserted {
            if let game = object as? Game {
                print("Game inserted: \(game.id)")
            } else if let player = object as? Player {
                print("Player inserted: \(player.id)")
            }
        }
        
        // Handle updated objects
        for object in updated {
            if let game = object as? Game {
                print("Game updated: \(game.id)")
            } else if let player = object as? Player {
                print("Player updated: \(player.id)")
            }
        }
        
        // Handle deleted objects
        for object in deleted {
            if let game = object as? Game {
                print("Game deleted: \(game.id)")
            } else if let player = object as? Player {
                print("Player deleted: \(player.id)")
            }
        }
    }
    
    // MARK: - Store Management
    private func loadPersistentStore() throws {
        var loadError: Error?
        let group = DispatchGroup()
        group.enter()
        
        container.loadPersistentStores { description, error in
            defer { group.leave() }
            if let error = error {
                loadError = error
            }
        }
        
        group.wait()
        
        if let error = loadError {
            throw PersistenceError.storeLoadFailed(error)
        }
        
        // Verify store version
        try verifyStoreVersion()
    }
    
    private func verifyStoreVersion() throws {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }
        
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL
        )
        
        guard let versionNumber = metadata["StoreVersionKey"] as? Int else { return }
        
        if versionNumber < StoreVersion.minimumCompatible {
            throw PersistenceError.incompatibleVersion(
                current: versionNumber,
                required: StoreVersion.minimumCompatible
            )
        }
    }
    
    private func handleLoadError(_ error: Error) {
        do {
            // Create backup if needed
            if Configuration.backupBeforeMigration {
                Task {
                    try await createBackup()
                }
            }
            
            // Try to recover
            try recoverFromLoadError(error)
        } catch {
            fatalError("Unrecoverable store error: \(error)")
        }
    }
    
    private func recoverFromLoadError(_ error: Error) throws {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            throw PersistenceError.recoveryFailed(error)
        }
        
        do {
            // Try to remove the store file
            try container.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL,
                ofType: NSSQLiteStoreType,
                options: [:]
            )
            
            // Try loading again
            var retryError: Error?
            let group = DispatchGroup()
            group.enter()
            
            container.loadPersistentStores { _, error in
                defer { group.leave() }
                retryError = error
            }
            
            group.wait()
            
            if let error = retryError {
                throw PersistenceError.recoveryFailed(error)
            }
        } catch {
            throw PersistenceError.recoveryFailed(error)
        }
    }
    
    // MARK: - Persistence Operations
    func save() throws {
        let context = container.viewContext
        if context.hasChanges {
            try context.save()
        }
    }
    
    // MARK: - Context Management
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    @BackupActor
    func createBackup() async throws {
        try await BackupManager.shared.createBackup()
    }
    
    func restoreFromBackup() async throws {
        try await BackupManager.shared.restoreFromLatestBackup()
    }
    
    // MARK: - Data Operations
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let context = container.newBackgroundContext()
            context.perform {
                do {
                    let result = try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func performWithRetry<T>(
        attempts: Int = Configuration.maxRetryAttempts,
        delay: TimeInterval = Configuration.retryDelay,
        operation: @escaping () throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...attempts {
            do {
                return try operation()
            } catch {
                lastError = error
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? PersistenceError.recoveryFailed(NSError(domain: "", code: -1))
    }
    
    // MARK: - Data Consistency
    func verifyDataConsistency() throws {
        let context = container.viewContext
        
        // Check games
        let gameRequest = NSFetchRequest<Game>(entityName: "Game")
        let games = try context.fetch(gameRequest)
        
        for game in games {
            try game.validateState()
            
            // Check rounds
            if let rounds = game.rounds as? Set<Round> {
                for round in rounds {
                    try round.validateState()
                }
            }
            
            // Check players
            if let players = game.players as? Set<Player> {
                for player in players {
                    try player.validateState()
                }
            }
        }
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: Error) {
        print("Persistence error: \(error)")
        // Add additional error handling as needed
    }
    
    // MARK: - Cleanup
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

