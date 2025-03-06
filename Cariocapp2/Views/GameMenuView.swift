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
        VStack(spacing: 16) {
            // Game Actions Section
            VStack(alignment: .leading, spacing: 12) {
                if let game = navigationCoordinator.getGame(id: gameID), game.isActive && !game.isComplete {
                    Text("Game Actions")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    HStack(spacing: 16) {
                        MenuButton(
                            title: "Resume",
                            icon: "play.circle",
                            action: { navigationCoordinator.dismissSheet() }
                        )
                        
                        MenuButton(
                            title: "Edit Scores",
                            icon: "pencil.circle",
                            action: { showingScoreEdit = true }
                        )
                        
                        MenuButton(
                            title: "Rules",
                            icon: "book",
                            action: {
                                navigationCoordinator.dismissSheet()
                                navigationCoordinator.path.append(.rules)
                            }
                        )
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            
            // Game Info Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Game Info")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                if let game = navigationCoordinator.getGame(id: gameID) {
                    InfoRow(label: "Started", value: game.startDate.formatted(date: .abbreviated, time: .shortened))
                    
                    InfoRow(label: "Current Round", value: getRoundDescription(game.currentRound))
                    
                    InfoRow(label: "Players", value: game.playersArray.map { $0.name }.joined(separator: ", "))
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            
            // Leave Game Section
            VStack {
                Button(action: {
                    showingLeaveConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                        Text("Leave Game")
                            .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .disabled(isLeaving)
            }
            
            Spacer()
        }
        .padding()
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
    
    // Helper component for menu buttons
    private struct MenuButton: View {
        let title: String
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.title2)
                    Text(title)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // Helper component for info rows
    private struct InfoRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
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