import SwiftUI
import CoreData

struct PlayerManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var repository: CoreDataPlayerRepository
    @State private var players: [Player] = []
    
    @State private var showingAddPlayer = false
    @State private var showingEditPlayer = false
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var playerName = ""
    @State private var errorMessage = ""
    @State private var selectedPlayer: Player?
    
    init() {
        print("🔍 PlayerManagementView - Initializing")
        // Initialize with empty context, will be updated in onAppear
        let repository = CoreDataPlayerRepository(context: NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType))
        self._repository = StateObject(wrappedValue: repository)
    }
    
    var body: some View {
        List {
            if players.isEmpty {
                ContentUnavailableView(
                    "No Players",
                    systemImage: "person.2",
                    description: Text("Add players to start managing them")
                )
            } else {
                ForEach(players) { player in
                    PlayerStatsRow(player: player)
                        .onLongPressGesture {
                            selectedPlayer = player
                            playerName = player.name
                            if player.activeGames.isEmpty {
                                showingDeleteConfirmation = true
                            } else {
                                showingEditPlayer = true
                            }
                        }
                        .contextMenu {
                            Button {
                                selectedPlayer = player
                                playerName = player.name
                                showingEditPlayer = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            if player.activeGames.isEmpty {
                                Button(role: .destructive) {
                                    selectedPlayer = player
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if player.activeGames.isEmpty {
                                Button(role: .destructive) {
                                    selectedPlayer = player
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            
                            Button {
                                selectedPlayer = player
                                playerName = player.name
                                showingEditPlayer = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .navigationTitle("Players")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPlayer = true
                } label: {
                    Label("Add Player", systemImage: "person.badge.plus")
                }
            }
        }
        .alert("Add Player", isPresented: $showingAddPlayer) {
            TextField("Player Name", text: $playerName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                playerName = ""
            }
            Button("Add") {
                addPlayer()
            }
            .disabled(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the player's name")
        }
        .alert("Edit Player", isPresented: $showingEditPlayer) {
            TextField("Player Name", text: $playerName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                playerName = ""
                selectedPlayer = nil
            }
            Button("Save") {
                if let player = selectedPlayer {
                    updatePlayer(player)
                }
            }
            .disabled(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the new name for the player")
        }
        .alert("Delete Player", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedPlayer = nil
            }
            Button("Delete", role: .destructive) {
                if let player = selectedPlayer {
                    deletePlayer(player)
                }
            }
        } message: {
            if let player = selectedPlayer {
                Text("Are you sure you want to delete \(player.name)?")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            print("🔍 PlayerManagementView appeared")
            print("🔍 Repository context: \(repository.context)")
            print("🔍 Environment context: \(viewContext)")
            
            // Update repository context with environment context
            repository.updateContext(viewContext)
            
            // Force a refresh of the context to ensure we have the latest data
            viewContext.refreshAllObjects()
            refreshPlayers()
        }
        .onChange(of: repository.context.hasChanges) { _, hasChanges in
            if hasChanges {
                refreshPlayers()
            }
        }
    }
    
    private func refreshPlayers() {
        do {
            // Use repository's fetchPlayers method to get only non-guest players
            let players = try repository.fetchPlayers(includeGuests: false)
            
            print("🔍 Debug - Found \(players.count) non-guest players in context:")
            for player in players {
                print("🔍 Player: \(player.name), isGuest: \(player.isGuest), id: \(player.id)")
            }
            
            // Update the players array
            self.players = players
            
            print("🔍 Players refreshed")
        } catch {
            print("❌ Failed to refresh players: \(error)")
            errorMessage = "Failed to refresh players"
            showingError = true
        }
    }
    
    private func addPlayer() {
        do {
            let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📝 Adding player with name: \(trimmedName)")
            
            if let existingPlayer = try repository.findPlayer(byName: trimmedName) {
                print("❌ Player with name already exists: \(existingPlayer.name)")
                errorMessage = "A player with this name already exists"
                showingError = true
                return
            }
            
            let player = try repository.createPlayer(name: trimmedName)
            print("✅ Player added successfully: \(player.name)")
            
            // Save context after adding player
            try repository.context.save()
            
            // Refresh the players list
            refreshPlayers()
            
            playerName = ""
            showingAddPlayer = false
            
        } catch let error as AppError {
            print("❌ Failed to add player: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
        } catch {
            print("❌ Unexpected error adding player: \(error.localizedDescription)")
            errorMessage = "An unexpected error occurred"
            showingError = true
        }
    }
    
    private func updatePlayer(_ player: Player) {
        do {
            let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📝 Updating player \(player.name) to: \(trimmedName)")
            
            if let existingPlayer = try repository.findPlayer(byName: trimmedName), existingPlayer != player {
                print("❌ Another player with this name exists: \(existingPlayer.name)")
                errorMessage = "A player with this name already exists"
                showingError = true
                return
            }
            
            player.name = trimmedName
            try repository.updatePlayer(player)
            
            // Save context after updating player
            try repository.context.save()
            
            // Refresh the players list
            refreshPlayers()
            
            playerName = ""
            selectedPlayer = nil
            showingEditPlayer = false
            
        } catch let error as AppError {
            print("❌ Failed to update player: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
        } catch {
            print("❌ Unexpected error updating player: \(error.localizedDescription)")
            errorMessage = "An unexpected error occurred"
            showingError = true
        }
    }
    
    private func deletePlayer(_ player: Player) {
        do {
            print("🗑️ Deleting player: \(player.name)")
            try repository.deletePlayer(player)
            
            // Save context after deleting player
            try repository.context.save()
            
            // Refresh the players list
            refreshPlayers()
            
            selectedPlayer = nil
        } catch let error as AppError {
            print("❌ Failed to delete player: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
        } catch {
            print("❌ Unexpected error deleting player: \(error.localizedDescription)")
            errorMessage = "An unexpected error occurred"
            showingError = true
        }
    }
}

struct PlayerManagementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PlayerManagementView()
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
} 