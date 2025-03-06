import Foundation

enum GameError: LocalizedError {
    case invalidPlayerCount(Int)
    case invalidDealerIndex(Int16, playerCount: Int)
    case gameNotFound
    case invalidGameState(String)
    case playerInActiveGame(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPlayerCount(let count):
            return "Invalid number of players: \(count). Must be between 2 and 4."
        case .invalidDealerIndex(let index, let count):
            return "Invalid dealer index: \(index). Must be between 0 and \(count - 1)."
        case .gameNotFound:
            return "Game not found."
        case .invalidGameState(let message):
            return "Invalid game state: \(message)"
        case .playerInActiveGame(let name):
            return "Player '\(name)' is already in an active game"
        }
    }
} 