import SwiftUI
import CoreData

// MARK: - Main View
struct ScoreEditView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var viewModel: GameViewModel
    
    // MARK: - Properties
    let gameID: UUID
    
    init(gameID: UUID) {
        self.gameID = gameID
        let coordinator = GameCoordinator(viewContext: PersistenceController.shared.container.viewContext)
        self._viewModel = StateObject(wrappedValue: GameViewModel.instance(for: gameID, coordinator: coordinator))
    }
    
    // MARK: - State
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedRound: Round?
    @State private var editedScores: [String: Int32] = [:]
    
    // MARK: - Computed Properties
    private var game: Game? {
        let request = Game.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", gameID as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    private var completedRounds: [Round] {
        game?.roundsArray.filter { $0.isCompleted && !$0.isSkipped } ?? []
    }
    
    private var selectedRoundScores: [(player: Player, score: Int32)] {
        guard let round = selectedRound,
              let game = game else { return [] }
        
        return game.playersArray.map { player in
            let scoreKey = player.id.uuidString
            let score = editedScores[scoreKey] ?? round.scores?[scoreKey] ?? 0
            return (player: player, score: score)
        }.sorted { $0.score < $1.score }
    }
    
    // MARK: - View Body
    var body: some View {
        NavigationStack {
            List {
                if completedRounds.isEmpty {
                    ContentUnavailableView(
                        "No Completed Rounds",
                        systemImage: "number.circle",
                        description: Text("Complete some rounds to edit their scores")
                    )
                } else {
                    Section("Select Round") {
                        ForEach(completedRounds) { round in
                            Button {
                                selectedRound = round
                                editedScores.removeAll()
                            } label: {
                                HStack {
                                    Text(round.name)
                                    Spacer()
                                    if selectedRound?.id == round.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    
                    if let round = selectedRound {
                        Section("Edit Scores") {
                            ForEach(selectedRoundScores, id: \.player.id) { score in
                                HStack {
                                    Text(score.player.name)
                                    Spacer()
                                    TextField("Score", value: binding(for: score.player), format: .number)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                }
                            }
                            
                            Button("Save Changes") {
                                saveScores()
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(editedScores.isEmpty)
                        }
                    }
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
        }
    }
    
    // MARK: - Helper Methods
    private func binding(for player: Player) -> Binding<Int32> {
        let key = player.id.uuidString
        return Binding(
            get: { editedScores[key] ?? selectedRound?.scores?[key] ?? 0 },
            set: { newValue in
                if newValue >= 0 {
                    editedScores[key] = newValue
                }
            }
        )
    }
    
    private func saveScores() {
        guard let round = selectedRound,
              !editedScores.isEmpty else { return }
        
        do {
            // Update scores
            var updatedScores = round.scores ?? [:]
            for (playerId, score) in editedScores {
                updatedScores[playerId] = score
            }
            round.scores = updatedScores
            
            // Save changes
            try viewContext.save()
            
            // Refresh game state
            if let game = game {
                Task {
                    try await viewModel.refreshGameState(game: game)
                }
            }
            
            // Clear state and dismiss
            editedScores.removeAll()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Preview
struct ScoreEditView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ScoreEditView(gameID: UUID())
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
} 