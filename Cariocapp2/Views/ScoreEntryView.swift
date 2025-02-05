import SwiftUI
import CoreData

struct ScoreEntryView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    
    // MARK: - Properties
    @StateObject private var viewModel: GameViewModel
    
    let gameID: UUID
    
    // MARK: - State
    @State private var scores: [UUID: String] = [:]  // Keep as String for text input
    @State private var isConfirmationPresented = false
    @State private var error: Error?
    @State private var isErrorPresented = false
    
    // MARK: - Constants
    private let maxScore = 999
    private let scoreRegex = try! NSRegularExpression(pattern: "^[0-9]*$")
    
    // MARK: - Initialization
    init(gameID: UUID) {
        self.gameID = gameID
        let coordinator = GameCoordinator(viewContext: PersistenceController.shared.container.viewContext)
        self._viewModel = StateObject(wrappedValue: GameViewModel.instance(for: gameID, coordinator: coordinator))
    }
    
    var body: some View {
        NavigationStack {
            if let game = viewModel.game {
                Form {
                    Section {
                        ForEach(game.playersArray) { player in
                            ScoreEntryRow(
                                player: player,
                                score: binding(for: player),
                                onScoreChange: { newValue in
                                    validateScore(newValue, for: player)
                                }
                            )
                        }
                    } header: {
                        Text("Enter scores for \(game.currentRoundDescription)")
                    } footer: {
                        Text("Enter the score for each player. Lower scores are better.")
                    }
                }
                .navigationTitle("Enter Scores")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            navigationCoordinator.dismissSheet()
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if validateScores() {
                                validateAndSubmitScores()
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Game Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The game may have been deleted")
                )
                .onAppear {
                    navigationCoordinator.dismissSheet()
                }
            }
        }
        .alert("Error", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(error?.localizedDescription ?? "")
        }
        .overlay {
            if isConfirmationPresented {
                LoadingOverlay(message: "Saving...")
            }
        }
        .task {
            do {
                if let game = try await viewModel.coordinator.verifyGame(id: gameID) {
                    try await viewModel.loadGame(game)
                    initializeGameState()
                }
            } catch {
                self.error = error
                isErrorPresented = true
            }
        }
    }
    
    // MARK: - Helper Methods
    private func initializeGameState() {
        guard let game = viewModel.game else { return }
        
        for player in game.playersArray {
            scores[player.id] = ""
        }
    }
    
    private var canSave: Bool {
        guard let game = viewModel.game,
              !scores.isEmpty else { return false }
        
        // All scores must be valid numbers
        for (_, score) in scores {
            if !isValidScore(score) {
                return false
            }
        }
        
        // At least one player must have a score of 0 (winner)
        return scores.values.contains { Int($0) == 0 }
    }
    
    private func binding(for player: Player) -> Binding<String> {
        Binding(
            get: { scores[player.id] ?? "" },
            set: { scores[player.id] = $0 }
        )
    }
    
    private func validateScore(_ score: String, for player: Player) {
        // Empty score is allowed during input
        guard !score.isEmpty else { return }
        
        // Validate numeric input
        let range = NSRange(location: 0, length: score.utf16.count)
        if scoreRegex.firstMatch(in: score, range: range) == nil {
            scores[player.id] = String(score.filter { $0.isNumber })
            return
        }
        
        // Validate maximum score
        if let numericScore = Int32(score), numericScore > maxScore {
            scores[player.id] = String(maxScore)
            showError("Maximum score is \(maxScore)")
        }
    }
    
    private var hasZeroScore: Bool {
        return scores.values.contains { score in
            guard let numericScore = Int32(score) else { return false }
            return numericScore == 0
        }
    }
    
    private func validateScoreInput(_ score: String) -> Bool {
        guard let numericScore = Int32(score) else { return false }
        return numericScore >= 0
    }
    
    private func isValidScore(_ score: String) -> Bool {
        guard let _ = Int32(score) else { return false }
        return true
    }
    
    private func validateScores() -> Bool {
        guard let game = viewModel.game else { return false }
        
        // Check if all scores are entered
        guard scores.count == game.playersArray.count else {
            showError("Please enter scores for all players")
            return false
        }
        
        // Check if all scores are valid numbers
        for (_, score) in scores {
            guard isValidScore(score) else {
                showError("Please enter valid numbers for all scores")
                return false
            }
        }
        
        // Check if at least one player has a score of 0
        let hasZeroScore = scores.values.contains { score in
            guard let numericScore = Int32(score) else { return false }
            return numericScore == 0
        }
        
        if !hasZeroScore {
            showError("At least one player must have a score of 0")
            return false
        }
        
        return true
    }
    
    private func validateAndSubmitScores() {
        guard validateScores() else { return }
        isConfirmationPresented = true
        
        // Convert scores to Int32 to match Core Data
        var finalScores: [String: Int32] = [:]
        for (playerID, scoreString) in scores {
            if let score = Int32(scoreString) {  // Convert directly to Int32
                finalScores[playerID.uuidString] = score  // Convert UUID to String
            }
        }
        
        Task {
            do {
                try await viewModel.submitScores(finalScores)
                
                // Check if this was the final round
                if let game = viewModel.game,
                   game.currentRound == Int16(game.maxRounds) {
                    navigationCoordinator.presentGameCompletion(for: gameID)
                } else {
                    navigationCoordinator.dismissSheet()
                }
            } catch {
                self.error = error
                isErrorPresented = true
            }
        }
    }
    
    private func showError(_ message: String) {
        error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
        isErrorPresented = true
    }
    
    private func cleanup() {
        scores.removeAll()
        isConfirmationPresented = false
    }
}

// MARK: - Supporting Views
private struct ScoreEntryRow: View {
    let player: Player
    let score: Binding<String>
    let onScoreChange: (String) -> Void
    
    var body: some View {
        HStack {
            Text(player.name)
                .font(.headline)
            Spacer()
            TextField("Score", text: score)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(width: 80)
                .onChange(of: score.wrappedValue) { _, newValue in
                    onScoreChange(newValue)
                }
        }
    }
}

// MARK: - Preview
struct ScoreEntryView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = NavigationCoordinator(viewContext: context)
        
        if let game = try? Game.createPreviewGame(in: context) {
            ScoreEntryView(gameID: game.id)
                .environment(\.managedObjectContext, context)
                .environmentObject(coordinator)
        }
    }
} 