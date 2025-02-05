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
        // Clean up any nil references
        activeInstances = activeInstances.filter { $0.value.instance != nil }
        
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
    private func withStateLock<T>(_ operation: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation()
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
    func preloadGame(_ game: Game) {
        print("🔍 GameViewModel[\(gameId)] - Starting preloadGame")
        print("🔍 GameViewModel[\(gameId)] - Game ID: \(game.id)")
        Task { @MainActor in
            do {
                try await loadGame(game)
            } catch {
                self.error = error
            }
        }
    }
    
    func loadGame(_ game: Game) async throws {
        print("🔍 GameViewModel[\(gameId)] - Starting game load")
        
        // Simulate some async work to ensure proper async context
        try await Task.sleep(nanoseconds: 1)
        
        // Verify game ID matches
        guard game.id == gameId else {
            print("🔍 GameViewModel[\(gameId)] - Game ID mismatch")
            throw GameError.invalidGameState("Game ID mismatch")
        }
        
        // Update state
        self.game = game
        currentRound = Int16(game.currentRound)
        dealer = game.playersArray[Int(game.dealerIndex)]
        starter = game.playersArray[(Int(game.dealerIndex) + 1) % game.playersArray.count]
        players = game.playersArray
        roundProgress = calculateRoundProgress(game)
        updateScores(for: game)
        updateCanEndRound()
        canSubmitScores = !game.roundsArray.contains { $0.number == game.currentRound && $0.isCompleted }
        shouldShowGameCompletion = game.isComplete
        
        // Reset or load firstCardColor based on current round
        if let currentRoundObj = game.roundsArray.first(where: { $0.number == game.currentRound }) {
            self.firstCardColor = currentRoundObj.firstCardColor.flatMap { FirstCardColor(rawValue: $0) }
        } else {
            self.firstCardColor = nil
        }
        
        print("🔍 GameViewModel[\(gameId)] - Game loaded successfully")
        print("🔍 GameViewModel[\(gameId)] - Current round: \(currentRound)")
        print("🔍 GameViewModel[\(gameId)] - Dealer: \(dealer?.name ?? "None")")
        print("🔍 GameViewModel[\(gameId)] - Starter: \(starter?.name ?? "None")")
        print("🔍 GameViewModel[\(gameId)] - Players: \(players.map { $0.name }.joined(separator: ", "))")
    }
    
    func refreshGameState() async throws {
        guard let game = try await coordinator.verifyGame(id: gameId) else { return }
        try await loadGame(game)
        objectWillChange.send()
    }
    
    func refreshGameState(game: Game) async throws {
        try await loadGame(game)
        objectWillChange.send()
    }
    
    private func updateScores(for game: Game) {
        print("📊 Starting score update for game \(game.id)")
        print("📊 Total rounds in game: \(game.roundsArray.count)")
        
        var newCurrentScores: [UUID: Int32] = [:]
        var newTotalScores: [UUID: Int32] = [:]
        
        // Log round details
        print("📊 Round details:")
        for round in game.roundsArray {
            print("  - Round \(round.number): completed=\(round.isCompleted), skipped=\(round.isSkipped), scores=\(round.scores ?? [:])")
        }
        
        // Update current round scores
        if let currentRoundScores = game.roundsArray.first(where: { $0.number == game.currentRound })?.scores {
            print("📊 Current round \(game.currentRound) scores: \(currentRoundScores)")
            for (playerId, score) in currentRoundScores {
                if let id = UUID(uuidString: playerId) {
                    newCurrentScores[id] = score
                }
            }
        }
        
        // Get completed non-skipped rounds for total score calculation
        let completedRounds = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }
        print("📊 Found \(completedRounds.count) completed non-skipped rounds for total score calculation")
        print("📊 Completed rounds: \(completedRounds.map { "Round \($0.number)" }.joined(separator: ", "))")
        
        // Calculate total scores
        for player in game.playersArray {
            print("📊 Calculating total for \(player.name) (ID: \(player.id)):")
            var totalScore: Int32 = 0
            
            for round in completedRounds {
                if let score = round.scores?[player.id.uuidString] {
                    print("  - Round \(round.number): Adding score \(score)")
                    totalScore += score
                } else {
                    print("  - Round \(round.number): No score found!")
                }
            }
            
            print("📊 Final total for \(player.name): \(totalScore)")
            newTotalScores[player.id] = totalScore
        }
        
        currentScores = newCurrentScores
        totalScores = newTotalScores
    }
    
    func cleanup() {
        print("🔍 GameViewModel[\(gameId)] - Starting cleanup")
        
        Task { @MainActor in
            // Cancel any pending operations
            isRefreshing = false
            
            // Clear state
            game = nil
            currentRound = 1
            players.removeAll()
            currentScores.removeAll()
            totalScores.removeAll()
            roundTransitionMessage = nil
            error = nil
            firstCardColor = nil
            
            isCleaning = false
        }
        
        print("🔍 GameViewModel[\(gameId)] - Cleanup complete")
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
        guard let game = self.game else { throw GameError.gameNotFound }
        
        // Create or update the round
        let round = game.roundsArray.first { $0.number == game.currentRound } ?? Round(context: game.managedObjectContext!)
        round.number = game.currentRound
        round.scores = scores
        round.isCompleted = true
        
        // Properly associate the round with the game if it's new
        if !game.roundsArray.contains(round) {
            game.addToRounds(round)
        }
        
        // Save changes
        try game.managedObjectContext?.save()
        
        // Check if this is round 12 or if all required rounds are completed
        if game.currentRound == Int16(game.maxRounds) || game.isComplete {
            // Mark game as complete and inactive
            game.isActive = false
            try game.managedObjectContext?.save()
            shouldShowGameCompletion = true
            return
        }
        
        // Only advance to next round if game is not complete
        game.currentRound += 1
        game.dealerIndex = Int16((Int(game.dealerIndex) + 1) % game.playersArray.count)
        try game.managedObjectContext?.save()
        
        // Refresh state
        try await loadGame(game)
    }
    
    func setFirstCardColor(_ color: FirstCardColor) async {
        guard let game = game,
              let context = game.managedObjectContext else { return }
        
        await context.perform {
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
}

enum FirstCardColor: String {
    case red = "red"
    case black = "black"
} 