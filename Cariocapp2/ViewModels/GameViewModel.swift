import Foundation
import CoreData
import SwiftUI
import Combine

/// ViewModel for managing game state and logic
@MainActor
final class GameViewModel: ObservableObject {
    // MARK: - Static Instance Management
    private static var activeInstances = [UUID: WeakGameViewModel]()
    private static let instanceLock = NSLock()
    
    private class WeakGameViewModel {
        weak var instance: GameViewModel?
        init(_ instance: GameViewModel) {
            self.instance = instance
        }
    }
    
    @MainActor
    static func instance(for gameId: UUID, coordinator: GameCoordinator) -> GameViewModel {
        // Use async-safe locking with Task
        Task {
            // Clean up any nil references
            activeInstances = activeInstances.filter { $0.value.instance != nil }
        }
        
        // Check if we already have an instance for this game ID
        if let existingInstance = activeInstances[gameId]?.instance {
            print("🔍 GameViewModel - Reusing existing instance for game ID: \(gameId)")
            return existingInstance
        }
        
        // Create new instance if none exists
        print("🔍 GameViewModel - Creating new instance for game ID: \(gameId)")
        let newInstance = GameViewModel(coordinator: coordinator, gameId: gameId)
        activeInstances[gameId] = WeakGameViewModel(newInstance)
        return newInstance
    }
    
    @MainActor
    static func instance(for gameId: UUID) -> GameViewModel {
        // Get the coordinator from the environment
        let coordinator = GameCoordinator.shared
        return instance(for: gameId, coordinator: coordinator)
    }
    
    // MARK: - Published Properties
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var currentRound: Int16 = 1
    @Published private(set) var dealer: Player?
    @Published private(set) var starter: Player?
    @Published private(set) var players: [Player] = []
    @Published private(set) var roundProgress: Double = 0.0
    @Published private(set) var currentScores: [UUID: Int32] = [:]
    @Published private(set) var totalScores: [UUID: Int32] = [:]
    @Published private(set) var roundTransitionMessage: String?
    @Published private(set) var game: Game?
    @Published private(set) var canEndRound: Bool = false
    @Published private(set) var canSubmitScores = false
    @Published private(set) var shouldShowGameCompletion = false
    @Published private(set) var firstCardColor: FirstCardColor?
    
    // MARK: - Properties
    let coordinator: GameCoordinator
    private let gameId: UUID
    private var cancellables = Set<AnyCancellable>()
    private var isCleaning = false
    private var isRefreshing = false
    private var loadTask: Task<Void, Never>?
    private let stateLock = NSLock()
    
    // MARK: - State Protection
    private func withStateLock<T>(_ operation: () async throws -> T) async throws -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try await operation()
    }
    
    // MARK: - Initialization
    private init(coordinator: GameCoordinator, gameId: UUID) {
        print("🔍 GameViewModel[\(gameId)] - Starting initialization")
        self.coordinator = coordinator
        self.gameId = gameId
        print("🔍 GameViewModel[\(gameId)] - Setting up observers")
        setupObservers()
        print("🔍 GameViewModel[\(gameId)] - Initialization complete")
    }
    
    deinit {
        print("🔍 GameViewModel[\(gameId)] - Starting deinit")
        loadTask?.cancel()
        cancellables.forEach { $0.cancel() }
        
        // Remove self from active instances
        let id = gameId // Capture the ID locally
        Task { @MainActor in
            Self.activeInstances.removeValue(forKey: id)
        }
        
        print("🔍 GameViewModel[\(gameId)] - Deinit complete")
    }
    
    // MARK: - Game State Management
    func preloadGame(_ game: Game) async throws {
        print("🔍 GameViewModel[\(self.gameId)] - Starting preloadGame")
        print("🔍 GameViewModel[\(self.gameId)] - Game ID: \(game.id)")
        try await self.loadGame(game)
    }
    
    func refreshGameState() async throws {
        guard !isRefreshing else {
            print("🔍 GameViewModel[\(self.gameId)] - Refresh already in progress, skipping")
            return
        }
        
        isRefreshing = true
        await MainActor.run { isLoading = true }
        
        defer {
            Task { @MainActor in
                isRefreshing = false
                isLoading = false
            }
        }
        
        print("🔍 GameViewModel[\(self.gameId)] - Refreshing game state")
        
        do {
            guard let game = try await coordinator.verifyGame(id: self.gameId) else {
                print("🔍 GameViewModel[\(self.gameId)] - Game not found")
                await MainActor.run {
                    self.game = nil
                    self.error = GameError.gameNotFound
                }
                return
            }
            
            guard game.isActive else {
                print("🔍 GameViewModel[\(self.gameId)] - Game is not active")
                await MainActor.run {
                    self.game = nil
                    self.error = GameError.invalidGameState("Game is not active")
                }
                return
            }
            
            try await self.loadGame(game)
            print("🔍 GameViewModel[\(self.gameId)] - Game state refreshed successfully")
        } catch {
            print("🔍 GameViewModel[\(self.gameId)] - Failed to refresh game state: \(error)")
            await MainActor.run { 
                self.error = error
                self.game = nil
            }
        }
    }
    
    func loadGame() {
        Task {
            do {
                try await refreshGameState()
            } catch {
                print("❌ GameViewModel[\(self.gameId)] - Failed to load game: \(error)")
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
    
    func loadGame(_ game: Game) async throws {
        print("🔍 GameViewModel[\(self.gameId)] - Starting game load")
        
        try await self.withStateLock { [weak self] in
            guard let self = self else { return }
            
            // Verify game ID matches
            guard game.id == self.gameId else {
                print("🔍 GameViewModel[\(self.gameId)] - Game ID mismatch")
                throw GameError.invalidGameState("Game ID mismatch")
            }
            
            print("🔍 GameViewModel[\(self.gameId)] - Updating game state")
            
            // Verify game has required relationships
            guard let players = game.players as? Set<Player>, !players.isEmpty else {
                print("🔍 GameViewModel[\(self.gameId)] - Game has no players")
                throw GameError.invalidGameState("Game has no players")
            }
            
            let playersArray = game.playersArray
            guard !playersArray.isEmpty else {
                print("🔍 GameViewModel[\(self.gameId)] - Game players array is empty")
                throw GameError.invalidGameState("Game players array is empty")
            }
            
            // Update state in a single MainActor run to prevent partial updates
            try await MainActor.run {
                self.game = game
                self.currentRound = Int16(game.currentRound)
                self.dealer = playersArray[Int(game.dealerIndex)]
                self.starter = playersArray[(Int(game.dealerIndex) + 1) % playersArray.count]
                self.players = playersArray
                self.roundProgress = self.calculateRoundProgress(game)
                self.updateScores(for: game)
                self.updateCanEndRound()
                self.canSubmitScores = !game.roundsArray.contains { $0.number == game.currentRound && $0.isCompleted }
                self.shouldShowGameCompletion = game.isComplete
                
                if let currentRoundObj = game.roundsArray.first(where: { $0.number == game.currentRound }) {
                    self.firstCardColor = currentRoundObj.firstCardColor.flatMap { FirstCardColor(rawValue: $0) }
                } else {
                    self.firstCardColor = nil
                }
            }
            
            print("🔍 GameViewModel[\(self.gameId)] - Game loaded successfully")
            print("🔍 GameViewModel[\(self.gameId)] - Current round: \(self.currentRound)")
            print("🔍 GameViewModel[\(self.gameId)] - Dealer: \(self.dealer?.name ?? "None")")
            print("🔍 GameViewModel[\(self.gameId)] - Starter: \(self.starter?.name ?? "None")")
            print("🔍 GameViewModel[\(self.gameId)] - Players: \(self.players.map { $0.name }.joined(separator: ", "))")
        }
    }
    
    private func updateScores(for game: Game) {
        print("📊 Starting score update for game \(game.id)")
        
        var newCurrentScores: [UUID: Int32] = [:]
        var newTotalScores: [UUID: Int32] = [:]
        
        // Get completed non-skipped rounds for total score calculation
        let completedRounds = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }
        print("📊 Found \(completedRounds.count) completed non-skipped rounds")
        
        // Calculate total scores for each player
        for player in game.playersArray {
            var totalScore: Int32 = 0
            
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    totalScore += score
                }
            }
            
            newTotalScores[player.id] = totalScore
            
            // Set current round score if available
            if let currentRoundScores = game.roundsArray.first(where: { $0.number == game.currentRound })?.scores {
                if let score = currentRoundScores[player.id.uuidString] {
                    newCurrentScores[player.id] = score
                }
            }
        }
        
        self.currentScores = newCurrentScores
        self.totalScores = newTotalScores
    }
    
    func cleanup() {
        print("🔍 GameViewModel[\(self.gameId)] - Starting cleanup")
        
        Task { @MainActor in
            guard !isCleaning else { return }
            isCleaning = true
            
            // Cancel any pending operations
            self.isRefreshing = false
            self.loadTask?.cancel()
            
            // Clear state
            self.game = nil
            self.currentRound = 1
            self.players.removeAll()
            self.currentScores.removeAll()
            self.totalScores.removeAll()
            self.roundTransitionMessage = nil
            self.error = nil
            self.firstCardColor = nil
            
            self.isCleaning = false
            
            print("🔍 GameViewModel[\(self.gameId)] - Cleanup complete")
        }
    }
    
    func cleanupOnDismiss() {
        cleanup()
        // Clear any cached instances
        Self.activeInstances.removeValue(forKey: gameId)
    }
    
    func handleScoreEntry(game: Game) async throws -> String? {
        guard let game = try await coordinator.verifyGame(id: game.id) else {
            throw GameError.gameNotFound
        }
        
        let currentRound = game.currentRound  // No conversion needed
        
        // Check if current round is complete
        if let round = game.roundsArray.first(where: { $0.number == currentRound }),
           round.isCompleted {
            // Move to next round
            let nextRound = currentRound + 1
            let nextDealerIndex = Int16((Int(game.dealerIndex) + 1) % players.count)
            try await coordinator.updateGameState(game, currentRound: nextRound, dealerIndex: nextDealerIndex)
            
            // Return transition message
            if let nextRoundRule = RoundRule.getRound(number: nextRound) {
                return "Starting Round \(nextRound): \(nextRoundRule.name)"
            }
        }
        
        return nil
    }
    
    // MARK: - Round Management
    func getCurrentRoundScore(for player: Player) -> Int32 {
        return currentScores[player.id] ?? 0
    }
    
    func getTotalScore(for player: Player) -> Int32 {
        return totalScores[player.id] ?? 0
    }
    
    func getRoundName() -> String {
        RoundRule.getRound(number: Int16(currentRound))?.name ?? "Unknown Round"
    }
    
    private func calculateRoundProgress(_ game: Game) -> Double {
        guard let currentRoundObj = game.roundsArray.first(where: { $0.number == game.currentRound }) else {
            return 0.0
        }
        
        let completedCount = currentRoundObj.scores?.count ?? 0
        return players.isEmpty ? 0.0 : Double(completedCount) / Double(players.count)
    }
    
    // MARK: - Observers
    private func setupObservers() {
        coordinator.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.error = error
            }
            .store(in: &cancellables)
    }
    
    /// Get the current round rule
    var currentRoundRule: RoundRule? {
        print("📱 GameViewModel - Getting round rule for round \(currentRound)")
        return RoundRule.getRound(number: Int16(currentRound))
    }
    
    /// Get the detailed description of the current round
    func getCurrentRoundDescription() -> String {
        let description = currentRoundRule?.description ?? "Unknown Round"
        print("📱 GameViewModel - Getting round description: \(description)")
        return description
    }
    
    /// Check if the current round is optional
    func isOptionalRound() -> Bool {
        let isOptional = currentRoundRule?.isOptional ?? false
        print("📱 GameViewModel - Checking if round is optional: \(isOptional)")
        return isOptional
    }
    
    /// Clear any error state
    func clearError() {
        print("📱 GameViewModel - Clearing error state")
        error = nil
    }
    
    // MARK: - Game State Updates
    func handleRoundCompletion() async throws {
        guard let game = try await coordinator.verifyGame(id: gameId) else {
            throw GameError.gameNotFound
        }
        
        // Update game state
        let nextRound = game.currentRound + 1  // Already Int16
        let nextDealerIndex = Int16((Int(game.dealerIndex) + 1) % players.count)
        
        // Reset first card color for the new round
        firstCardColor = nil  // Reset view model state
        
        // Update game state
        try await coordinator.updateGameState(game, currentRound: nextRound, dealerIndex: nextDealerIndex)
        
        // Refresh view model state
        try await loadGame(game)
    }
    
    // MARK: - Computed Properties
    var isCurrentRoundOptional: Bool {
        guard let game = game else { return false }
        return RoundRule.getRound(number: game.currentRound)?.isOptional ?? false
    }
    
    private func updateCanEndRound() {
        guard let game = game else {
            canEndRound = false
            return
        }
        
        // Get current round if it exists
        if let currentRoundObj = game.roundsArray.first(where: { $0.number == game.currentRound }) {
            // Can't end a completed round
            if currentRoundObj.isCompleted {
                canEndRound = false
                return
            }
            
            // If it's a skipped round, we can end it
            if currentRoundObj.isSkipped {
                canEndRound = true
                return
            }
        }
        
        // For rounds that don't exist yet or normal rounds, we can end them
        // (scores will be entered in ScoreEntryView)
        canEndRound = true
    }
    
    // MARK: - Game Actions
    func skipCurrentRound() async {
        guard let game = game else { return }
        
        do {
            try await coordinator.skipRound(gameID: game.id)
            try await refreshGameState()
            updateCanEndRound()
        } catch {
            self.error = error
        }
    }
    
    func submitScores(_ scores: [String: Int32]) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("🎮 Submitting scores for round \(game?.currentRound ?? 0)")
            try await coordinator.submitScores(gameID: gameId, scores: scores)
            
            // Verify and load the game after submitting scores
            if let updatedGame = try await coordinator.verifyGame(id: gameId) {
                try await loadGame(updatedGame)
                
                // Check if this was the last round and game is complete
                if updatedGame.isComplete {
                    print("🎮 Game is complete after submitting scores for round \(updatedGame.currentRound)")
                    shouldShowGameCompletion = true
                }
            } else {
                throw GameError.gameNotFound
            }
        } catch {
            print("❌ Failed to submit scores: \(error)")
            self.error = error
            throw error
        }
    }
    
    func setFirstCardColor(_ color: FirstCardColor) async {
        guard let game = self.game,
              let context = game.managedObjectContext else { return }
        
        await context.perform { [weak self] in
            guard let self = self else { return }
            // Get or create current round
            let currentRound = game.roundsArray.first { $0.number == game.currentRound } ?? Round(context: context)
            if currentRound.game == nil {
                currentRound.game = game
                currentRound.number = game.currentRound
                game.addToRounds(currentRound)
            }
            
            // Set the color
            currentRound.firstCardColor = color.rawValue
            self.firstCardColor = color
            try? context.save()
        }
    }
    
    // MARK: - State Management
    private func updateState(_ operation: @escaping () async throws -> Void) async throws {
        self.isRefreshing = true
        defer { self.isRefreshing = false }
        
        try await self.withStateLock {
            try await operation()
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Error Handling
    func setError(_ error: Error?) {
        Task { @MainActor in
            self.error = error
        }
    }
}

enum FirstCardColor: String {
    case red = "red"
    case black = "black"
} 