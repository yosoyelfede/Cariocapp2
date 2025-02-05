import XCTest
import CoreData
@testable import Cariocapp2

@MainActor
final class GameCoordinatorTests: XCTestCase {
    // MARK: - Properties
    private var coordinator: GameCoordinator!
    private var context: NSManagedObjectContext!
    private var container: NSPersistentContainer!
    
    // MARK: - Setup
    override func setUp() async throws {
        try await super.setUp()
        
        // Create in-memory persistent container
        container = NSPersistentContainer(name: "Cariocapp2")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        await withCheckedContinuation { continuation in
            container.loadPersistentStores { description, error in
                if let error = error {
                    fatalError("Failed to load test store: \(error)")
                }
                continuation.resume()
            }
        }
        
        context = container.viewContext
        coordinator = GameCoordinator(viewContext: context)
    }
    
    override func tearDown() async throws {
        coordinator = nil
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Test Game Creation
    func testGameCreation() async throws {
        let game = try Game.createGame(
            players: [player1, player2],
            dealerIndex: 0,
            context: context
        )
        
        XCTAssertNotNil(game)
        XCTAssertEqual(game.playersArray.count, 2)
        XCTAssertEqual(game.currentRound, 1)
        XCTAssertEqual(game.dealerIndex, 0)
    }
    
    func testGameWithGuests() async throws {
        let guestPlayers = [(id: UUID(), name: "Guest 1")]
        
        let game = try repository.createGameWithGuests(
            registeredPlayers: [player1],
            guestPlayers: guestPlayers,
            dealerIndex: 0
        )
        
        XCTAssertNotNil(game)
        XCTAssertEqual(game.playersArray.count, 2)
        XCTAssertTrue(game.playersArray.contains { $0.name == "Guest 1" })
    }
    
    // MARK: - Test Game Deletion
    func testGameDeletion() async throws {
        let game = try Game.createGame(
            players: [player1, player2],
            dealerIndex: 0,
            context: context
        )
        
        try await coordinator.deleteGame(game)
        
        let fetchRequest = Game.fetchRequest()
        let games = try context.fetch(fetchRequest)
        XCTAssertTrue(games.isEmpty)
    }
    
    // MARK: - Test Game State Updates
    func testUpdateGameState() async throws {
        // Create a game
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        // Update game state
        try await coordinator.updateGameState(game, currentRound: 2, dealerIndex: 1)
        
        // Verify updates
        let updatedGame = try coordinator.verifyGame(id: game.id)
        XCTAssertNotNil(updatedGame)
        XCTAssertEqual(updatedGame?.currentRound, 2)
        XCTAssertEqual(updatedGame?.dealerIndex, 1)
    }
    
    func testUpdateNonexistentGame() async throws {
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        // Delete game from context directly
        context.delete(game)
        try context.save()
        
        // Attempt to update through coordinator
        await assertThrowsError(GameError.gameNotFound) {
            try await coordinator.updateGameState(game, currentRound: 2, dealerIndex: 1)
        }
    }
    
    // MARK: - Test Game Completion
    func testCompleteGame() async throws {
        // Create a game
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        // Complete game
        try await coordinator.completeGame(game)
        
        // Verify game state
        let completedGame = try coordinator.verifyGame(id: game.id)
        XCTAssertNotNil(completedGame)
        XCTAssertFalse(completedGame?.isActive ?? true)
    }
    
    // MARK: - Helper Methods
    private func createTestPlayers(count: Int) throws -> [Player] {
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
    
    private func assertThrowsError<T: Error>(_ expectedError: T, file: StaticString = #file, line: UInt = #line, operation: () async throws -> Void) async where T: Equatable {
        do {
            try await operation()
            XCTFail("Expected error \(expectedError) was not thrown", file: file, line: line)
        } catch let error as T {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Expected error \(expectedError) but got \(error)", file: file, line: line)
        }
    }
} 