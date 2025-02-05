import SwiftUI
import CoreData

// MARK: - Array Extension
extension Array {
    mutating func rotate(by offset: Int) {
        let offset = offset % count
        self = Array(self[offset...] + self[..<offset])
    }
}

// MARK: - Main View
struct NewGameView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var container: DependencyContainer
    
    @StateObject private var repository: CoreDataPlayerRepository
    @StateObject private var coordinator: GameCoordinator
    @State private var registeredPlayers: [Player] = []
    
    // MARK: - State
    @State private var selectedPlayerIds: Set<UUID> = []
    @State private var guestPlayers: Set<GuestPlayer> = []
    @State private var newPlayerName: String = ""
    @State private var dealerIndex = 0
    @State private var navigateToGame = false
    @State private var createdGameID: UUID?
    
    // MARK: - Alert State
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // MARK: - Sheet State
    @State private var isAddingGuest = false
    @State private var showingPlayerSelection = false
    @State private var isCreatingGame = false
    
    // MARK: - Animation
    private let addPlayerTransition = AnyTransition.asymmetric(
        insertion: .scale.combined(with: .opacity),
        removal: .scale.combined(with: .opacity)
    )
    
    // MARK: - Initialization
    init() {
        print("🎮 NewGameView - Initializing")
        let context = PersistenceController.shared.container.viewContext
        self._repository = StateObject(wrappedValue: CoreDataPlayerRepository(context: context))
        self._coordinator = StateObject(wrappedValue: GameCoordinator(viewContext: context))
        print("🎮 NewGameView initialized")
    }
    
    // MARK: - Computed Properties
    private var selectedPlayers: [Player] {
        registeredPlayers.filter { selectedPlayerIds.contains($0.id) }
    }
    
    private var playersList: [(id: String, name: String, isGuest: Bool)] {
        let registered = selectedPlayers.map { (id: $0.id.uuidString, name: $0.name, isGuest: false) }
        let guests = guestPlayers.map { (id: $0.id.uuidString, name: $0.name, isGuest: true) }
        return (registered + guests).sorted { $0.name < $1.name }
    }
    
    private var playerCount: Int {
        selectedPlayers.count + guestPlayers.count
    }
    
    private var canStartGame: Bool {
        playerCount >= 2 && playerCount <= 4 && !isCreatingGame
    }
    
    private var validationMessage: String? {
        if playerCount == 0 {
            return "Add at least 2 players to start a game"
        } else if playerCount == 1 {
            return "Add 1 more player to start a game"
        } else if playerCount > 4 {
            return "Maximum 4 players allowed"
        }
        return nil
    }
    
    // MARK: - View Body
    var body: some View {
        Form {
            playerSelectionSection
            addPlayersSection
            dealerSelectionSection
        }
        .navigationTitle("New Game")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            print("🎮 NewGameView appeared")
            // Update contexts with environment context
            coordinator.updateContext(viewContext)
            repository.updateContext(viewContext)
            // Clear any existing selections
            selectedPlayerIds.removeAll()
            guestPlayers.removeAll()
            // Refresh player list
            refreshPlayers()
        }
        .onChange(of: viewContext) { _ in
            print("🎮 NewGameView - Context changed, refreshing players")
            coordinator.updateContext(viewContext)
            repository.updateContext(viewContext)
            refreshPlayers()
        }
        .alert("Add Guest Player", isPresented: $isAddingGuest) {
            TextField("Guest Name", text: $newPlayerName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                newPlayerName = ""
            }
            Button("Add") {
                addGuestPlayer()
            }
            .disabled(newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .modifier(StartGameToolbar(isEnabled: canStartGame, action: createGame))
        .navigationDestination(isPresented: $navigateToGame) {
            gameDestination
        }
        .loading(isCreatingGame, message: "Creating game...")
    }
    
    // MARK: - View Components
    private var playerSelectionSection: some View {
        Section {
            if playersList.isEmpty {
                ContentUnavailableView(
                    "No Players Selected",
                    systemImage: "person.2",
                    description: Text("Add players to start a game")
                )
                .transition(.opacity)
            } else {
                ForEach(playersList, id: \.id) { player in
                    PlayerRow(name: player.name, isGuest: player.isGuest) {
                        removePlayer(player)
                    }
                    .transition(addPlayerTransition)
                }
            }
        } header: {
            HStack {
                Text("Players")
                Spacer()
                Text("\(playerCount)/4")
                    .foregroundColor(playerCount > 4 ? .red : .secondary)
                    .fontWeight(playerCount > 4 ? .bold : .regular)
            }
        } footer: {
            if let message = validationMessage {
                Text(message)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var addPlayersSection: some View {
        Section {
            if registeredPlayers.isEmpty {
                ContentUnavailableView(
                    "No Players Available",
                    systemImage: "person.slash",
                    description: Text("Add players in the Players tab first")
                )
            } else {
                ForEach(registeredPlayers) { player in
                    let isSelected = selectedPlayerIds.contains(player.id)
                    Button(action: {
                        withAnimation {
                            if isSelected {
                                selectedPlayerIds.remove(player.id)
                            } else if playerCount < 4 {
                                selectedPlayerIds.insert(player.id)
                            }
                            updateDealerIndex()
                        }
                    }) {
                        HStack {
                            Label(player.name, systemImage: "person")
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .disabled(!isSelected && playerCount >= 4)
                }
            }

            Button(action: { isAddingGuest = true }) {
                Label("Add Guest Player", systemImage: "person.fill.questionmark")
            }
            .disabled(playerCount >= 4)
            .accessibilityHint(playerCount >= 4 ? "Maximum players reached" : "Add a guest player to the game")
        } header: {
            Text("Available Players")
        }
    }
    
    private var dealerSelectionSection: some View {
        Section(header: Text("Select Dealer")) {
            if !playersList.isEmpty {
                if dynamicTypeSize > .xxxLarge {
                    menuStylePicker
                } else {
                    wheelStylePicker
                }
            } else {
                Text("Add players to select a dealer")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var menuStylePicker: some View {
        let players = playersList
        return Picker("Dealer", selection: $dealerIndex) {
            ForEach(0..<players.count, id: \.self) { index in
                Text(players[index].name).tag(index)
            }
        }
        .pickerStyle(.menu)
    }
    
    private var wheelStylePicker: some View {
        let players = playersList
        return Picker("Dealer", selection: $dealerIndex) {
            ForEach(0..<players.count, id: \.self) { index in
                Text(players[index].name).tag(index)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 100) // Fixed height for the wheel picker
    }
    
    // MARK: - Actions
    private func removePlayer(_ player: (id: String, name: String, isGuest: Bool)) {
        withAnimation {
            if player.isGuest {
                if let guestToRemove = guestPlayers.first(where: { $0.id.uuidString == player.id }) {
                    guestPlayers.remove(guestToRemove)
                }
            } else {
                selectedPlayerIds.remove(UUID(uuidString: player.id)!)
            }
            updateDealerIndex()
        }
    }
    
    private func addGuestPlayer() {
        let trimmedName = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            withAnimation {
                let guest = try? GuestPlayer(name: trimmedName)
                if let guest = guest {
                    guestPlayers.insert(guest)
                    newPlayerName = ""
                }
            }
        }
    }
    
    private func updateDealerIndex() {
        dealerIndex = min(dealerIndex, max(0, playerCount - 1))
    }
    
    // MARK: - Game Creation
    private func createGame() {
        print("🎮 Creating new game")
        isCreatingGame = true
        
        Task { @MainActor in
            do {
                print("🎮 Selected players: \(selectedPlayers.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
                print("🎮 Guest players: \(guestPlayers.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
                print("🎮 Dealer index: \(dealerIndex)")
                
                // Get selected players
                let selectedPlayers = registeredPlayers.filter { selectedPlayerIds.contains($0.id) }
                
                // Map guest players to tuples
                let guestPlayerTuples = guestPlayers.map { guest in
                    (id: guest.id, name: guest.name)
                }
                
                // Create game with selected players and guests
                print("🎮 Creating game with coordinator...")
                let game = try await coordinator.createGame(
                    players: selectedPlayers,
                    guestPlayers: guestPlayerTuples,
                    dealerIndex: Int16(dealerIndex)
                )
                
                print("🎮 Game created with ID: \(game.id)")
                print("🎮 Game created, saving context...")
                try viewContext.save()
                
                // Verify game exists in context
                print("🎮 Verifying game...")
                if let verifiedGame = try await coordinator.verifyGame(id: game.id) {
                    print("🎮 Game verified successfully: \(verifiedGame.id)")
                    print("🎮 Players in game: \(verifiedGame.playersArray.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
                    
                    await MainActor.run {
                        self.createdGameID = verifiedGame.id
                        self.navigateToGame = true
                    }
                } else {
                    print("❌ Game verification failed")
                    throw GameError.gameNotFound
                }
            } catch {
                print("❌ Failed to create game: \(error)")
                print("❌ Detailed error: \(String(describing: error))")
                
                await MainActor.run {
                    alertTitle = "Error"
                    alertMessage = error.localizedDescription
                    showingAlert = true
                    createdGameID = nil
                    navigateToGame = false
                }
            }
            
            await MainActor.run {
                isCreatingGame = false
            }
        }
    }

    // MARK: - Navigation
    @ViewBuilder
    private var gameDestination: some View {
        if let gameID = createdGameID {
            GameView(gameID: gameID)
                .onAppear {
                    print("🎮 GameView appeared for game: \(gameID)")
                }
        } else {
            ContentUnavailableView(
                "Game Not Found",
                systemImage: "exclamationmark.triangle",
                description: Text("The game could not be created")
            )
        }
    }
    
    private func refreshPlayers() {
        do {
            let players = try repository.fetchPlayers(includeGuests: false)
            print("🎮 Fetched \(players.count) players")
            print("🎮 Players: \(players.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
            registeredPlayers = players
        } catch {
            print("❌ Failed to fetch players: \(error)")
            errorMessage = "Failed to load players"
            showingError = true
        }
    }
}

// MARK: - Preview
struct NewGameView_Previews: PreviewProvider {
    static var previews: some View {
        let previewContainer = PersistenceController.preview
        let context = previewContainer.container.viewContext
        
        NavigationStack {
            NewGameView()
                .environment(\.managedObjectContext, context)
                .environmentObject(DependencyContainer(persistenceController: previewContainer))
        }
    }
}

// MARK: - Custom Toolbar Modifier
private struct StartGameToolbar: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: action) {
                    Text("Start Game")
                }
                .disabled(!isEnabled)
            }
        }
    }
} 