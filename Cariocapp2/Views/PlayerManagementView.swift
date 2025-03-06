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
        // Initialize with shared PersistenceController
        let repository = CoreDataPlayerRepository(context: PersistenceController.shared.container.viewContext)
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
                            showingEditPlayer = true
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
            
            // Only refresh players if the array is empty
            if players.isEmpty {
                refreshPlayers(forceCleanup: true)
            }
        }
        .onChange(of: repository.context.hasChanges) { hasChanges in
            if hasChanges {
                // Only refresh the list, don't trigger statistics updates
                refreshPlayers(forceCleanup: false)
            }
        }
    }
    
    private func refreshPlayers(forceCleanup: Bool = false) {
        do {
            // If cleanup is requested, perform it before fetching players
            if forceCleanup {
                try repository.cleanupAbandonedGames()
            }
            
            // Use repository's fetchPlayers method to get only non-guest players
            let players = try repository.fetchPlayers(includeGuests: false)
            
            print("🔍 Debug - Found \(players.count) non-guest players in context:")
            for player in players {
                print("🔍 Player: \(player.name), isGuest: \(player.isGuest), id: \(player.id)")
            }
            
            // Update the players array
            self.players = players.filter { !$0.isDeleted && $0.managedObjectContext != nil }
            
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
            print("🗑️ Starting deletion of player: \(player.name)")
            
            // Get all games associated with this player
            let games = player.gamesArray
            print("🗑️ Player has \(games.count) total games")
            
            // Debug active games
            let activeGames = player.activeGames
            print("🗑️ Player has \(activeGames.count) active games")
            for game in activeGames {
                print("🗑️ Active game: \(game.id), isActive: \(game.isActive), isComplete: \(game.isComplete)")
            }
            
            // Force refresh the context to ensure we have the latest data
            viewContext.refreshAllObjects()
            
            // First, fix any games that are complete but still marked as active
            for game in games where game.isActive {
                if game.isComplete {
                    print("🗑️ Found completed game marked as active: \(game.id)")
                    game.isActive = false
                    game.endDate = Date()
                    try viewContext.save()
                }
            }
            
            // Refresh player data after fixing games
            viewContext.refreshAllObjects()
            
            // Verify no active games first
            guard player.activeGames.isEmpty else {
                // Try to fix any games that might be incorrectly marked as active
                print("🗑️ Attempting to fix active games")
                for game in player.activeGames {
                    if game.isComplete {
                        print("🗑️ Found completed game marked as active: \(game.id)")
                        game.isActive = false
                        game.endDate = Date()
                        try viewContext.save()
                    }
                }
                
                // Check again after fixing
                if !player.activeGames.isEmpty {
                    throw AppError.invalidPlayerState("Cannot delete player with active games")
                }
                return
            }
            
            // First delete all completed games
            print("🗑️ Deleting \(games.count) associated games")
            for game in games where !game.isActive {
                print("🗑️ Deleting game: \(game.id)")
                // Delete the game first, which will handle its own cleanup
                viewContext.delete(game)
            }
            
            // Save after game deletions
            try viewContext.save()
            
            // Now break player relationships
            print("🗑️ Breaking relationships for player: \(player.name)")
            player.games = NSSet()
            try viewContext.save()
            
            // Finally delete the player
            print("🗑️ Deleting player object")
            viewContext.delete(player)
            
            // Clear selection
            selectedPlayer = nil
            
            // Final save
            try viewContext.save()
            print("🗑️ Player deletion completed successfully")
            
            // Refresh the view
            viewContext.refreshAllObjects()
            refreshPlayers()
            
        } catch let error as AppError {
            print("❌ Failed to delete player: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
        } catch {
            print("❌ Unexpected error deleting player: \(error)")
            errorMessage = "An unexpected error occurred while deleting the player"
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