import XCTest
import CoreData
@testable import Cariocapp2

@MainActor
final class GameViewModelTests: XCTestCase {
    // MARK: - Properties
    private var viewModel: GameViewModel!
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
        viewModel = GameViewModel(coordinator: coordinator)
    }
    
    override func tearDown() async throws {
        viewModel = nil
        coordinator = nil
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Test Game Loading
    func testLoadGame() async throws {
        // Create test game
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        // Load game in view model
        await viewModel.loadGame(game)
        
        // Verify view model state
        XCTAssertEqual(viewModel.currentRound, 1)
        XCTAssertEqual(viewModel.players.count, 3)
        XCTAssertEqual(viewModel.dealer?.id, players[0].id)
        XCTAssertEqual(viewModel.starter?.id, players[1].id)
        XCTAssertEqual(viewModel.roundProgress, 0.0)
    }
    
    func testLoadNonexistentGame() async throws {
        // Create and delete a game
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        context.delete(game)
        try context.save()
        
        // Attempt to load deleted game
        await viewModel.loadGame(game)
        
        // Verify error state
        XCTAssertNotNil(viewModel.error)
        if let error = viewModel.error as? GameError {
            XCTAssertEqual(error, GameError.gameNotFound)
        }
    }
    
    // MARK: - Test Score Management
    func testScoreCalculation() async throws {
        // Create test game
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        // Add scores to current round
        if let round = game.roundsArray.first {
            round.scores = [
                players[0].id.uuidString: 10,
                players[1].id.uuidString: 20,
                players[2].id.uuidString: 30
            ]
            try context.save()
        }
        
        // Load game and verify scores
        await viewModel.loadGame(game)
        
        XCTAssertEqual(viewModel.getCurrentRoundScore(for: players[0]), 10)
        XCTAssertEqual(viewModel.getCurrentRoundScore(for: players[1]), 20)
        XCTAssertEqual(viewModel.getCurrentRoundScore(for: players[2]), 30)
    }
    
    func testRoundProgress() async throws {
        // Create test game
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        // Add scores for some players
        if let round = game.roundsArray.first {
            round.scores = [
                players[0].id.uuidString: 10,
                players[1].id.uuidString: 20
            ]
            try context.save()
        }
        
        // Load game and verify progress
        await viewModel.loadGame(game)
        
        XCTAssertEqual(viewModel.roundProgress, 2.0/3.0)
    }
    
    // MARK: - Test Round Management
    func testHandleScoreEntry() async throws {
        // Create test game
        let players = try createTestPlayers(count: 3)
        let game = try await coordinator.createGame(
            players: players,
            dealerIndex: 0
        )
        
        // Complete current round
        if let round = game.roundsArray.first {
            round.scores = [
                players[0].id.uuidString: 10,
                players[1].id.uuidString: 20,
                players[2].id.uuidString: 30
            ]
            round.isCompleted = true
            try context.save()
        }
        
        // Handle score entry
        let message = try await viewModel.handleScoreEntry(game: game)
        
        // Verify round transition
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("Round 2") ?? false)
        
        // Verify game state
        let updatedGame = try coordinator.verifyGame(id: game.id)
        XCTAssertEqual(updatedGame?.currentRound, 2)
        XCTAssertEqual(updatedGame?.dealerIndex, 1)
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
    
    func testGameCreation() throws {
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
    
    func testGameWithGuests() throws {
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
    
    func testGameDeletion() throws {
        let game = try Game.createGame(
            players: [player1, player2],
            dealerIndex: 0,
            context: context
        )
        
        try repository.deleteGame(game)
        
        let fetchRequest = Game.fetchRequest()
        let games = try context.fetch(fetchRequest)
        XCTAssertTrue(games.isEmpty)
    }
} 