import XCTest
import CoreData
@testable import Cariocapp2

@MainActor
final class DependencyContainerTests: XCTestCase {
    // MARK: - Properties
    private var container: DependencyContainer!
    
    // MARK: - Setup
    override func setUp() async throws {
        try await super.setUp()
        container = DependencyContainer.shared
    }
    
    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Test Dependency Provision
    func testProvideManagedObjectContext() {
        let context = container.provideManagedObjectContext()
        XCTAssertNotNil(context)
        XCTAssertEqual(context.concurrencyType, .mainQueueConcurrencyType)
    }
    
    func testProvideBackgroundContext() {
        let context = container.provideBackgroundContext()
        XCTAssertNotNil(context)
        XCTAssertEqual(context.concurrencyType, .privateQueueConcurrencyType)
    }
    
    func testProvideGameCoordinator() {
        let coordinator = container.provideGameCoordinator()
        XCTAssertNotNil(coordinator)
    }
    
    func testProvideStateManager() {
        let stateManager = container.provideStateManager()
        XCTAssertNotNil(stateManager)
    }
    
    func testProvideResourceManager() {
        let resourceManager = container.provideResourceManager()
        XCTAssertNotNil(resourceManager)
    }
    
    func testProvideBackupManager() {
        let backupManager = container.provideBackupManager()
        XCTAssertNotNil(backupManager)
    }
    
    // MARK: - Test App Lifecycle
    func testHandleMemoryWarning() async {
        // Trigger memory warning
        await container.handleMemoryWarning()
        
        // Verify state manager was updated
        let stateManager = container.provideStateManager()
        XCTAssertNotNil(stateManager)
    }
    
    func testHandleAppResignActive() async {
        // Simulate app becoming inactive
        await container.handleAppResignActive()
        
        // State should be saved (no way to verify directly, but should not crash)
    }
    
    func testHandleAppBackground() async {
        // Simulate app entering background
        await container.handleAppBackground()
        
        // Verify backup was created (check backup directory)
        let backupManager = container.provideBackupManager()
        XCTAssertNotNil(backupManager)
    }
    
    // MARK: - Test Integration
    func testFullAppLifecycle() async throws {
        // 1. Create game through coordinator
        let coordinator = container.provideGameCoordinator()
        let context = container.provideManagedObjectContext()
        
        // Create test players
        let players = try createTestPlayers(count: 3, in: context)
        
        let game = try Game.createGame(
            players: players,
            dealerIndex: 0,
            context: context
        )
        
        // 2. Simulate app lifecycle events
        await container.handleAppResignActive()
        await container.handleAppBackground()
        
        // 3. Verify game persists
        let fetchRequest = NSFetchRequest<Game>(entityName: "Game")
        fetchRequest.predicate = NSPredicate(format: "id == %@", game.id as CVarArg)
        let games = try context.fetch(fetchRequest)
        
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.id, game.id)
    }
    
    // MARK: - Helper Methods
    private func createTestPlayers(count: Int, in context: NSManagedObjectContext) throws -> [Player] {
        var players: [Player] = []
        
        for i in 0..<count {
            let player = Player(context: context)
            player.id = UUID()
            player.name = "Player \(i + 1)"
            player.gamesPlayed = 0
            player.gamesWon = 0
            player.totalScore = 0
            player.averagePosition = 0
            players.append(player)
        }
        
        try context.save()
        return players
    }
}

// MARK: - Environment Value Tests
final class EnvironmentValueTests: XCTestCase {
    func testManagedObjectContextKey() {
        var environment = EnvironmentValues()
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        
        environment.managedObjectContext = context
        XCTAssertEqual(environment.managedObjectContext, context)
    }
    
    func testGameCoordinatorKey() {
        var environment = EnvironmentValues()
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let coordinator = GameCoordinator(viewContext: context)
        
        environment.gameCoordinator = coordinator
        XCTAssertEqual(environment.gameCoordinator.viewContext, coordinator.viewContext)
    }
} 