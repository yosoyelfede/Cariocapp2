import SwiftUI
import CoreData

// MARK: - Main View
struct ScoreEditView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
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
                List {
                    if rounds.isEmpty {
                        ContentUnavailableView(
                            "No Rounds",
                            systemImage: "number.circle",
                            description: Text("No rounds available to edit")
                        )
                    } else {
                        Section("Rounds") {
                            ForEach(rounds.sorted(by: { $0.number < $1.number })) { round in
                                RoundScoreEditRow(
                                    round: round,
                                    isSelected: selectedRound?.id == round.id,
                                    editedScores: $editedScores,
                                    onSelect: {
                                        if selectedRound?.id == round.id {
                                            // Deselect if already selected
                                            selectedRound = nil
                                        } else {
                                            // Select this round
                                            selectedRound = round
                                            // Load scores for this round
                                            loadScoresForRound(round)
                                        }
                                    }
                                )
                            }
                        }
                        
                        if selectedRound != nil && !editedScores.isEmpty {
                            Section {
                                Button("Save Changes") {
                                    saveScores()
                                }
                                .frame(maxWidth: .infinity)
                                .disabled(editedScores.isEmpty)
                            }
                        }
                    }
                }
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                }
            }
            .navigationTitle("Edit Scores")
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
            .task {
                await loadGame()
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
    
    private func saveScores() {
        guard let selectedRound = selectedRound else { return }
        
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
}

// MARK: - Round Score Edit Row
struct RoundScoreEditRow: View {
    let round: Round
    let isSelected: Bool
    @Binding var editedScores: [String: Int32]
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Round header (always visible)
            Button(action: onSelect) {
                HStack {
                    Text("Round \(round.number)")
                        .font(.headline)
                    
                    if let firstCardColor = round.firstCardColor {
                        Text("(\(firstCardColor))")
                            .font(.subheadline)
                            .foregroundColor(firstCardColor == "red" ? .red : .primary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            // Player scores (only visible when selected)
            if isSelected {
                Divider()
                
                ForEach(round.game?.playersArray ?? [], id: \.id) { player in
                    HStack {
                        Text(player.name)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        TextField("Score", value: binding(for: player), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color(.secondarySystemBackground) : Color.clear)
        .cornerRadius(8)
    }
    
    private func binding(for player: Player) -> Binding<Int32> {
        let key = player.id.uuidString
        return Binding(
            get: { editedScores[key] ?? round.scores?[key] ?? 0 },
            set: { newValue in
                if newValue >= 0 {
                    editedScores[key] = newValue
                }
            }
        )
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