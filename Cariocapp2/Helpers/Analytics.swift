import Foundation

enum AnalyticsEvent {
    case appLaunch
    case gameStarted(playerCount: Int, includesOptionalRounds: Bool)
    case gameCompleted(duration: TimeInterval, playerCount: Int)
    case roundCompleted(roundNumber: Int16, duration: TimeInterval)
    case playerAdded(isGuest: Bool)
    case playerRemoved
    case error(AppError)
    
    var name: String {
        switch self {
        case .appLaunch: return "app_launch"
        case .gameStarted: return "game_started"
        case .gameCompleted: return "game_completed"
        case .roundCompleted: return "round_completed"
        case .playerAdded: return "player_added"
        case .playerRemoved: return "player_removed"
        case .error: return "error_occurred"
        }
    }
    
    var parameters: [String: Any] {
        switch self {
        case .appLaunch:
            return [:]
        case .gameStarted(let playerCount, let includesOptionalRounds):
            return [
                "player_count": playerCount,
                "includes_optional_rounds": includesOptionalRounds
            ]
        case .gameCompleted(let duration, let playerCount):
            return [
                "duration": duration,
                "player_count": playerCount
            ]
        case .roundCompleted(let roundNumber, let duration):
            return [
                "round_number": roundNumber,
                "duration": duration
            ]
        case .playerAdded(let isGuest):
            return ["is_guest": isGuest]
        case .playerRemoved:
            return [:]
        case .error(let error):
            return [
                "error_type": String(describing: type(of: error)),
                "error_description": error.localizedDescription
            ]
        }
    }
}

enum Analytics {
    static func track(_ event: AnalyticsEvent) {
        #if DEBUG
        Logger.debugOnly("Analytics: \(event.name) - \(event.parameters)")
        #else
        // Here you would integrate with your analytics service
        // For example: Firebase, Mixpanel, etc.
        #endif
    }
    
    static func setUserProperty(_ value: Any?, forName name: String) {
        #if DEBUG
        Logger.debugOnly("Analytics User Property: \(name) = \(String(describing: value))")
        #endif
    }
    
    static func logError(_ error: Error) {
        if let appError = error as? AppError {
            track(.error(appError))
        } else {
            let appError = AppError.coreDataError(error.localizedDescription)
            track(.error(appError))
        }
    }
} 