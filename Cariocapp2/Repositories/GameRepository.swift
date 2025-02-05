import CoreData
import Foundation

class GameRepository: ObservableObject {
    private var context: NSManagedObjectContext
    @Published private(set) var activeGames: [Game] = []
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    func updateContext(_ newContext: NSManagedObjectContext) {
        self.context = newContext
    }
    
    func fetchActiveGames() {
        let request = Game.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Game.startDate, ascending: false)]
        request.predicate = NSPredicate(format: "isActive == true")
        activeGames = ((try? context.fetch(request)) ?? []).filter { !$0.isComplete }
    }
    
    func createGame(players: [Player], dealerIndex: Int16) throws -> Game {
        // Validate input
        guard players.count >= 2 && players.count <= 4 else {
            throw GameError.invalidPlayerCount(players.count)
        }
        
        guard dealerIndex >= 0 && dealerIndex < Int16(players.count) else {
            throw GameError.invalidDealerIndex(dealerIndex, playerCount: players.count)
        }
        
        // Create game
        return try Game.createGame(
            players: players,
            dealerIndex: dealerIndex,
            context: context
        )
    }
    
    func createGameWithGuests(registeredPlayers: [Player], guestPlayers: [(id: UUID, name: String)], dealerIndex: Int16) throws -> Game {
        // Create guest players
        let guestPlayerObjects = guestPlayers.map { guest -> Player in
            let player = Player(context: context)
            player.id = guest.id
            player.name = guest.name
            player.isGuest = true
            return player
        }
        
        // Combine registered and guest players
        let allPlayers = registeredPlayers + guestPlayerObjects
        
        // Create game with all players
        return try createGame(
            players: allPlayers,
            dealerIndex: dealerIndex
        )
    }
    
    func getGame(id: UUID) throws -> Game? {
        let request = Game.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    func getAllGames() throws -> [Game] {
        let request = Game.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Game.startDate, ascending: false)]
        return try context.fetch(request)
    }
    
    func deleteGame(_ game: Game) throws {
        context.delete(game)
        try context.save()
    }
} 