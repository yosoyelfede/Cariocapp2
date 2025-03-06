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
    @State private var scores: [UUID: Int32] = [:]  // Changed from String to Int32
    @State private var isConfirmationPresented = false
    @State private var error: Error?
    @State private var isErrorPresented = false
    @State private var isScoreValid = false
    
    // MARK: - Constants
    private let maxScore = 999
    
    // MARK: - Initialization
    init(gameID: UUID) {
        self.gameID = gameID
        self._viewModel = StateObject(wrappedValue: GameViewModel.instance(for: gameID))
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
                                onIncrement: { incrementScore(for: player) },
                                onDecrement: { decrementScore(for: player) }
                            )
                        }
                    } header: {
                        Text("Enter scores for \(game.currentRoundDescription)")
                    } footer: {
                        // Validation status
                        HStack {
                            if !isScoreValid {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Exactly one player must have a score of 0")
                                    .font(.footnote)
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Scores are valid")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.top, 8)
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
                            validateAndSubmitScores()
                        }
                        .disabled(!isScoreValid)
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
                showError("Error loading game: \(error.localizedDescription)")
            }
        }
        .onChange(of: scores) { _, _ in
            validateScores()
        }
    }
    
    // MARK: - Helper Methods
    private func initializeGameState() {
        guard let game = viewModel.game else { return }
        
        for player in game.playersArray {
            scores[player.id] = 0
        }
        validateScores()
    }
    
    private func binding(for player: Player) -> Binding<Int32> {
        Binding(
            get: { scores[player.id] ?? 0 },
            set: { newValue in
                if newValue >= 0 {
                    scores[player.id] = newValue
                }
            }
        )
    }
    
    private func incrementScore(for player: Player) {
        let currentScore = scores[player.id] ?? 0
        if currentScore < maxScore {
            scores[player.id] = currentScore + 1
        }
    }
    
    private func decrementScore(for player: Player) {
        let currentScore = scores[player.id] ?? 0
        if currentScore > 0 {
            scores[player.id] = currentScore - 1
        }
    }
    
    private func validateScores() {
        guard let game = viewModel.game else {
            isScoreValid = false
            return
        }
        
        // Check if all scores are entered
        guard scores.count == game.playersArray.count else {
            isScoreValid = false
            return
        }
        
        // Count players with score of 0
        let zeroScoreCount = scores.values.filter { $0 == 0 }.count
        
        // Valid if exactly one player has a score of 0 and all players have scores
        isScoreValid = zeroScoreCount == 1
    }
    
    private func validateAndSubmitScores() {
        guard isScoreValid else { return }
        isConfirmationPresented = true
        
        // Convert scores to the format expected by the view model
        var finalScores: [String: Int32] = [:]
        for (playerID, score) in scores {
            finalScores[playerID.uuidString] = score
        }
        
        Task {
            do {
                try await viewModel.submitScores(finalScores)
                
                // Check if this was the final round and game is complete
                if let game = viewModel.game, game.isComplete {
                    print("🎮 Game is complete, navigating to game summary")
                    navigationCoordinator.dismissSheet()
                    navigationCoordinator.navigateToGameSummary(gameID)
                } else {
                    navigationCoordinator.dismissSheet()
                }
            } catch {
                showError("Error saving scores: \(error.localizedDescription)")
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
    let score: Binding<Int32>
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    
    var body: some View {
        HStack {
            Text(player.name)
                .font(.headline)
            
            Spacer()
            
            HStack(spacing: 0) {
                Button {
                    onDecrement()
                } label: {
                    Image(systemName: "minus")
                        .padding(8)
                }
                .disabled(score.wrappedValue <= 0)
                
                TextField("Score", value: score, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(score.wrappedValue == 0 ? Color.green : Color.clear, lineWidth: 2)
                    )
                
                Button {
                    onIncrement()
                } label: {
                    Image(systemName: "plus")
                        .padding(8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.quaternarySystemFill))
            )
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