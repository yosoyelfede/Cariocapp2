import SwiftUI
import CoreData

// MARK: - Main View
struct GameMenuView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    
    let gameID: UUID
    
    // MARK: - State
    @State private var showingLeaveConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLeaving = false
    @State private var isLoading = false
    @State private var showingScoreEdit = false
    
    // MARK: - View Body
    var body: some View {
        List {
            Section {
                if let game = navigationCoordinator.getGame(id: gameID), game.isActive && !game.isComplete {
                    Button(action: { navigationCoordinator.dismissSheet() }) {
                        Label("Resume Game", systemImage: "play.circle")
                    }
                    
                    Button {
                        showingScoreEdit = true
                    } label: {
                        Label("Edit Scores", systemImage: "pencil.circle")
                    }
                    
                    Button {
                        navigationCoordinator.dismissSheet()
                        navigationCoordinator.path.append(.rules)
                    } label: {
                        Label("Rules", systemImage: "book")
                    }
                }
            }
            
            Section("Game Info") {
                if let game = navigationCoordinator.getGame(id: gameID) {
                    LabeledContent("Started") {
                        Text(game.startDate, style: .date)
                            .foregroundColor(.secondary)
                    }
                    
                    LabeledContent("Current Round") {
                        Text(getRoundDescription(game.currentRound))
                            .foregroundColor(.secondary)
                    }
                    
                    LabeledContent("Players") {
                        Text(game.playersArray.map { $0.name }.joined(separator: ", "))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            
            Section {
                Button(role: .destructive, action: {
                    showingLeaveConfirmation = true
                }) {
                    Label("Leave Game", systemImage: "xmark.circle")
                }
                .disabled(isLeaving)
            }
        }
        .navigationTitle("Game Menu")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Leave Game", isPresented: $showingLeaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                leaveGame()
            }
        } message: {
            Text("Are you sure you want to leave this game? The game will be deleted and this action cannot be undone.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if isLoading {
                LoadingOverlay(message: "Loading...")
            }
        }
        .sheet(isPresented: $showingScoreEdit) {
            if let game = navigationCoordinator.getGame(id: gameID), 
               let currentRound = game.roundsArray.first(where: { $0.number == game.currentRound }) {
                ScoreEditView(gameID: gameID, roundID: currentRound.id)
                    .environmentObject(navigationCoordinator)
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getRoundDescription(_ roundNumber: Int16) -> String {
        RoundRule.getRound(number: roundNumber)?.name ?? "Unknown Round"
    }
    
    // MARK: - Actions
    private func leaveGame() {
        guard !isLeaving else { return }
        isLeaving = true
        isLoading = true
        
        Task {
            do {
                try await navigationCoordinator.deleteGame(gameID)
                await MainActor.run {
                    navigationCoordinator.dismissSheet()
                    navigationCoordinator.popToRoot()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isLeaving = false
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview
struct GameMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = NavigationCoordinator(viewContext: context)
        
        if let game = try? Game.createPreviewGame(in: context) {
            NavigationStack {
                GameMenuView(gameID: game.id)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(coordinator)
            }
        }
    }
} 