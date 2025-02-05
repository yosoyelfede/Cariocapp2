import SwiftUI
import CoreData

// MARK: - View State
private enum ViewState: Equatable {
    case loading
    case content
    case error(String)
    
    static func == (lhs: ViewState, rhs: ViewState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):
            return true
        case (.content, .content):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Preview State
private enum PreviewState {
    case loading
    case error(String)
    case ready(Game)
}

struct GameView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var viewModel: GameViewModel
    
    let gameID: UUID
    
    init(gameID: UUID) {
        self.gameID = gameID
        let coordinator = GameCoordinator(viewContext: PersistenceController.shared.container.viewContext)
        self._viewModel = StateObject(wrappedValue: GameViewModel.instance(for: gameID, coordinator: coordinator))
    }
    
    var body: some View {
        Group {
            if let game = viewModel.game {
                if game.isComplete {
                    ContentUnavailableView(
                        "Game Completed",
                        systemImage: "checkmark.circle",
                        description: Text("This game has been completed. You can view the results in Game History.")
                    )
                    .onAppear {
                        navigationCoordinator.popToRoot()
                    }
                } else {
                    gameContent(game)
                }
            } else {
                VStack {
                    ProgressView()
                    Text("Loading game...")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    navigationCoordinator.presentGameMenu(for: gameID)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            ToolbarItem(placement: .principal) {
                Text("Round \(viewModel.currentRound)")
                    .font(.headline)
            }
        }
        .task {
            viewModel.coordinator.updateContext(viewContext)
            await loadGameWithRetries()
        }
        .onChange(of: viewContext) { oldValue, newValue in
            print("🎮 GameView - Context changed, updating coordinator")
            viewModel.coordinator.updateContext(newValue)
        }
        .onChange(of: viewModel.shouldShowGameCompletion) { oldValue, newValue in
            if newValue {
                navigationCoordinator.presentGameCompletion(for: gameID)
            }
        }
    }
    
    private func loadGameWithRetries() async {
        let maxRetries = 5
        let retryDelay: UInt64 = 500_000_000 // 0.5 seconds
        
        for attempt in 1...maxRetries {
            print("🎮 GameView - Loading attempt \(attempt)/\(maxRetries)")
            
            do {
                if let game = try await viewModel.coordinator.verifyGame(id: gameID) {
                    print("🎮 GameView - Game found on attempt \(attempt)")
                    try await viewModel.loadGame(game)
                    print("🎮 GameView - Game loaded successfully")
                    return
                }
                
                print("🎮 GameView - Game not found on attempt \(attempt)")
                
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: retryDelay)
                }
            } catch {
                print("🎮 GameView - Error loading game on attempt \(attempt): \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: retryDelay)
                }
            }
        }
        
        print("🎮 GameView - Failed to load game after \(maxRetries) attempts")
        // After all retries failed, navigate back
        navigationCoordinator.popToRoot()
    }
    
    @ViewBuilder
    private func gameContent(_ game: Game) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    gameInfoSection(game)
                    currentRoundSection(game)
                    firstCardColorSection(game)
                    playerScoresSection(game)
                }
                .padding(.vertical)
            }
            
            VStack {
                Divider()
                
                if viewModel.isCurrentRoundOptional {
                    Button(action: {
                        Task {
                            await viewModel.skipCurrentRound()
                        }
                    }) {
                        Text("Skip Round")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                Button(action: {
                    navigationCoordinator.presentScoreEntry(for: gameID)
                }) {
                    Text("End Round")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.canEndRound ? Color.accentColor : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!viewModel.canEndRound)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func gameInfoSection(_ game: Game) -> some View {
        VStack(spacing: 12) {
            HStack {
                Label {
                    Text("Dealer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                }
                
                Spacer()
                
                Text(game.dealer?.name ?? "Unknown")
                    .font(.headline)
            }
            
            HStack {
                Label {
                    Text("Starter")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "person.fill")
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(game.starter?.name ?? "Unknown")
                    .font(.headline)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func currentRoundSection(_ game: Game) -> some View {
        let roundInfo = RoundRule.getRound(number: game.currentRound)
        
        return VStack(spacing: 8) {
            Text(roundInfo?.name ?? "Unknown Round")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(roundInfo?.description ?? "")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func firstCardColorSection(_ game: Game) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("First Card Color")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 20) {
                Button {
                    Task {
                        await viewModel.setFirstCardColor(.red)
                    }
                } label: {
                    Label("Red", systemImage: viewModel.firstCardColor == .red ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }
                
                Button {
                    Task {
                        await viewModel.setFirstCardColor(.black)
                    }
                } label: {
                    Label("Black", systemImage: viewModel.firstCardColor == .black ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func playerScoresSection(_ game: Game) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Scores")
                    .font(.headline)
                Spacer()
            }
            
            ForEach(game.playersArray) { player in
                let totalScore: Int32 = viewModel.getTotalScore(for: player)
                PlayerScoreRow(
                    player: player,
                    currentRoundScore: nil,
                    totalScore: totalScore,
                    isDealer: game.dealer?.id == player.id
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Preview
struct GameView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = NavigationCoordinator(viewContext: context)
        
        if let game = try? Game.createPreviewGame(in: context) {
            NavigationStack {
                GameView(gameID: game.id)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(coordinator)
            }
        }
    }
} 