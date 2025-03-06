import SwiftUI
import CoreData

// MARK: - Main View
struct ScoreEditView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @Environment(\.gameCoordinator) private var coordinator
    @StateObject private var viewModel: GameViewModel
    
    // MARK: - Properties
    let gameID: UUID
    let roundID: UUID
    
    init(gameID: UUID, roundID: UUID) {
        self.gameID = gameID
        self.roundID = roundID
        self._viewModel = StateObject(wrappedValue: GameViewModel.instance(for: gameID, coordinator: GameCoordinator(viewContext: PersistenceController.shared.container.viewContext)))
    }
    
    // MARK: - State
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedRound: Round?
    @State private var editedScores: [String: Int32] = [:]
    @State private var isLoading = false
    @State private var rounds: [Round] = []
    @State private var isScoreValid = false
    @State private var showingRules = false
    
    // MARK: - Computed Properties
    private var game: Game? {
        let request = Game.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", gameID as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    // MARK: - View Body
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with rules
                    VStack(spacing: 12) {
                        Text("Edit Round Scores")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        Button {
                            showingRules.toggle()
                        } label: {
                            HStack {
                                Image(systemName: "info.circle")
                                Text("Scoring Rules")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    
                    if rounds.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No Rounds",
                            systemImage: "number.circle",
                            description: Text("No rounds available to edit")
                        )
                        Spacer()
                    } else {
                        // Round selection
                        ScrollView {
                            VStack(spacing: 16) {
                                // Round selection
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SELECT ROUND")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 16)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(rounds.sorted(by: { $0.number < $1.number })) { round in
                                                Button {
                                                    if selectedRound?.id == round.id {
                                                        selectedRound = nil
                                                        isScoreValid = false
                                                    } else {
                                                        selectedRound = round
                                                        loadScoresForRound(round)
                                                        validateScores()
                                                    }
                                                } label: {
                                                    Text("Round \(round.number)")
                                                        .font(.subheadline)
                                                        .fontWeight(selectedRound?.id == round.id ? .bold : .regular)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 8)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .fill(selectedRound?.id == round.id ? 
                                                                      Color.accentColor : 
                                                                      Color(.tertiarySystemFill))
                                                        )
                                                        .foregroundColor(selectedRound?.id == round.id ? .white : .primary)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                                
                                // Score editing
                                if let selectedRound = selectedRound {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("PLAYER SCORES")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 16)
                                        
                                        VStack(spacing: 0) {
                                            ForEach(selectedRound.game?.playersArray ?? [], id: \.id) { player in
                                                VStack(spacing: 0) {
                                                    HStack {
                                                        Text(player.name)
                                                            .font(.body)
                                                        
                                                        Spacer()
                                                        
                                                        HStack(spacing: 0) {
                                                            Button {
                                                                decrementScore(for: player)
                                                            } label: {
                                                                Image(systemName: "minus")
                                                                    .padding(8)
                                                            }
                                                            .disabled(editedScores[player.id.uuidString] == 0)
                                                            
                                                            TextField("Score", value: binding(for: player), format: .number)
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
                                                                        .stroke(editedScores[player.id.uuidString] == 0 ? Color.green : Color.clear, lineWidth: 2)
                                                                )
                                                            
                                                            Button {
                                                                incrementScore(for: player)
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
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 12)
                                                    
                                                    if player.id != selectedRound.game?.playersArray.last?.id {
                                                        Divider()
                                                            .padding(.leading, 16)
                                                    }
                                                }
                                            }
                                        }
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .cornerRadius(12)
                                        .padding(.horizontal, 16)
                                    }
                                    
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
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                    
                                    Spacer()
                                    
                                    // Save button
                                    Button(action: saveScores) {
                                        Text("Save Changes")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(isScoreValid ? Color.accentColor : Color.gray.opacity(0.5))
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                    .disabled(!isScoreValid)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 16)
                                } else {
                                    Spacer()
                                    Text("Select a round to edit scores")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.top, 32)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                
                if isLoading {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingRules) {
                ScoringRulesView()
            }
            .task {
                await loadGame()
            }
            .onChange(of: editedScores) { _, _ in
                validateScores()
            }
        }
    }
    
    // MARK: - Helper Methods
    private func loadGame() async {
        isLoading = true
        
        do {
            // Get the game from the view context
            let request = Game.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", gameID as CVarArg)
            request.fetchLimit = 1
            
            if let game = try viewContext.fetch(request).first {
                // Get all completed rounds
                rounds = game.roundsArray.filter { $0.isCompleted && !$0.isSkipped }
                
                // If roundID is specified, select that round
                if let specificRound = rounds.first(where: { $0.id == roundID }) {
                    selectedRound = specificRound
                    loadScoresForRound(specificRound)
                    validateScores()
                }
            } else {
                errorMessage = "Game not found"
                showingError = true
            }
        } catch {
            errorMessage = "Error loading game: \(error.localizedDescription)"
            showingError = true
        }
        
        isLoading = false
    }
    
    private func loadScoresForRound(_ round: Round) {
        if let scores = round.scores {
            editedScores = scores
        } else {
            editedScores = [:]
        }
    }
    
    private func validateScores() {
        guard let game = game, let selectedRound = selectedRound else {
            isScoreValid = false
            return
        }
        
        // Count players with score of 0
        let zeroScoreCount = editedScores.values.filter { $0 == 0 }.count
        
        // Ensure all players have scores
        let allPlayersHaveScores = game.playersArray.allSatisfy { player in
            editedScores[player.id.uuidString] != nil
        }
        
        // Valid if exactly one player has a score of 0 and all players have scores
        isScoreValid = zeroScoreCount == 1 && allPlayersHaveScores
    }
    
    private func incrementScore(for player: Player) {
        let key = player.id.uuidString
        let currentScore = editedScores[key] ?? 0
        editedScores[key] = currentScore + 1
    }
    
    private func decrementScore(for player: Player) {
        let key = player.id.uuidString
        let currentScore = editedScores[key] ?? 0
        if currentScore > 0 {
            editedScores[key] = currentScore - 1
        }
    }
    
    private func saveScores() {
        guard let selectedRound = selectedRound, isScoreValid else { return }
        
        isLoading = true
        
        Task {
            do {
                print("🔄 Saving edited scores for round \(selectedRound.id)")
                print("🔄 Edited scores: \(editedScores)")
                
                // Update the round scores
                let updatedRound = try await coordinator.updateRoundScores(roundID: selectedRound.id, scores: editedScores)
                if updatedRound != nil {
                    print("✅ Round scores updated successfully")
                    
                    // Force refresh the game state to ensure changes are reflected
                    try await viewModel.refreshGameState()
                    
                    // Force refresh the context
                    viewContext.refreshAllObjects()
                    
                    // Notify the game view to update
                    try await navigationCoordinator.refreshGameState(gameID)
                    
                    // Add a small delay to ensure UI updates
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Successfully updated
                    dismiss()
                } else {
                    errorMessage = "Failed to update scores"
                    showingError = true
                }
            } catch {
                print("❌ Error updating scores: \(error)")
                errorMessage = "Error updating scores: \(error.localizedDescription)"
                showingError = true
            }
            
            isLoading = false
        }
    }
    
    private func binding(for player: Player) -> Binding<Int32> {
        let key = player.id.uuidString
        return Binding(
            get: { editedScores[key] ?? 0 },
            set: { newValue in
                if newValue >= 0 {
                    editedScores[key] = newValue
                }
            }
        )
    }
}

// MARK: - Scoring Rules View
struct ScoringRulesView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Carioca Scoring Rules")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("In Carioca, the scoring follows these key principles:")
                            .font(.body)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint(text: "The player who completes the round first gets a score of 0")
                            BulletPoint(text: "All other players score points based on the cards left in their hands")
                            BulletPoint(text: "Exactly one player must have a score of 0 in each round")
                            BulletPoint(text: "Lower scores are better - the player with the lowest total wins")
                        }
                        
                        Text("Card Values")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Ace: 15 points")
                            Text("• K, Q, J: 10 points each")
                            Text("• Number cards: Face value (2-10)")
                            Text("• Joker: 25 points")
                        }
                        .font(.subheadline)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Scoring Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct ScoreEditView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ScoreEditView(gameID: UUID(), roundID: UUID())
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
} 