import Foundation
import CoreData
import SwiftUI

/// Container for managing app dependencies
@MainActor
final class DependencyContainer: ObservableObject {
    // MARK: - Properties
    static let shared = DependencyContainer()
    
    private let persistenceController: PersistenceController
    private var resourceManager: ResourceManager?
    private var backupManager: BackupManager?
    private let stateManager: AppState
    private var gameCoordinator: GameCoordinator?
    
    // MARK: - Initialization
    private init() {
        // Initialize persistence first
        self.persistenceController = PersistenceController.shared
        
        // Create state manager with context
        let context = persistenceController.container.viewContext
        self.stateManager = AppState(viewContext: context)
        
        // Initialize resource manager
        self.resourceManager = ResourceManager()
        
        Task {
            // Initialize other actors on background
            await initializeActors()
        }
        
        setupObservers()
    }
    
    // For preview support
    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        let context = persistenceController.container.viewContext
        self.stateManager = AppState(viewContext: context)
        self.resourceManager = ResourceManager()
    }
    
    // MARK: - Actor Initialization
    private func initializeActors() async {
        self.backupManager = await BackupManager.shared
    }
    
    // MARK: - Public Interface
    func provideManagedObjectContext() -> NSManagedObjectContext {
        persistenceController.container.viewContext
    }
    
    func provideBackgroundContext() -> NSManagedObjectContext {
        persistenceController.newBackgroundContext()
    }
    
    func provideGameCoordinator() -> GameCoordinator {
        if let coordinator = gameCoordinator {
            return coordinator
        }
        let coordinator = GameCoordinator(viewContext: provideManagedObjectContext())
        gameCoordinator = coordinator
        return coordinator
    }
    
    func provideStateManager() -> AppState {
        stateManager
    }
    
    func provideResourceManager() -> ResourceManager {
        if let manager = resourceManager {
            return manager
        }
        let manager = ResourceManager()
        resourceManager = manager
        return manager
    }
    
    func provideBackupManager() async -> BackupManager {
        if let manager = backupManager {
            return manager
        }
        let manager = await BackupManager.shared
        backupManager = manager
        return manager
    }
    
    // MARK: - Configuration
    private func setupObservers() {
        // Observe memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleMemoryWarning()
            }
        }
        
        // Observe app state changes
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await self?.handleAppResignActive()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await self?.handleAppBackground()
            }
        }
    }
    
    // MARK: - Event Handlers
    func handleMemoryWarning() async {
        do {
            let resourceManager = provideResourceManager()
            try await resourceManager.checkResources()
            await stateManager.updateResourceState()
        } catch {
            print("Failed to handle memory warning: \(error)")
        }
    }
    
    func handleAppResignActive() async throws {
        try await stateManager.saveApplicationState()
        try persistenceController.save()
    }
    
    func handleAppBackground() async throws {
        do {
            // Create backup if needed
            if let backupManager = await backupManager {
                try await backupManager.createBackup()
            }
            
            // Save state
            try await stateManager.saveApplicationState()
            try persistenceController.save()
            
            // Check resources
            if let resourceManager = resourceManager {
                try await resourceManager.checkResources()
            }
        } catch {
            print("Failed to handle app background: \(error)")
            throw error
        }
    }
}

// MARK: - Environment Values
struct ManagedObjectContextKey: EnvironmentKey {
    static let defaultValue: NSManagedObjectContext = PersistenceController.preview.container.viewContext
}

struct GameCoordinatorKey: EnvironmentKey {
    @MainActor
    static var defaultValue: GameCoordinator {
        GameCoordinator(viewContext: PersistenceController.preview.container.viewContext)
    }
}

extension EnvironmentValues {
    var managedObjectContext: NSManagedObjectContext {
        get { self[ManagedObjectContextKey.self] }
        set { self[ManagedObjectContextKey.self] = newValue }
    }
    
    var gameCoordinator: GameCoordinator {
        get { self[GameCoordinatorKey.self] }
        set { self[GameCoordinatorKey.self] = newValue }
    }
} 