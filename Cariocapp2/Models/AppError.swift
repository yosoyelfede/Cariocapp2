import Foundation

/// Represents the strategy for recovering from an error
public enum RecoveryStrategy {
    case retry(maxAttempts: Int)
    case retryWithBackoff(initial: TimeInterval, multiplier: Double, maxAttempts: Int)
    case abort
    case rollback
    case userPrompt(message: String)
}

public enum AppError: LocalizedError {
    // Data Layer Errors
    case coreDataError(String)
    case concurrentModification(String)
    case migrationError(String)
    case persistenceError(String)
    case dataCorruption(String)
    
    // Game Logic Errors
    case invalidGameState(String)
    case invalidPlayerState(String)
    case invalidRoundState(String)
    case scoreError(String)
    
    // Validation Errors
    case validationError(String)
    case inputValidation(String)
    case stateValidation(String)
    
    // Resource Errors
    case resourceConstraint(String)
    case diskSpace(String)
    case memoryWarning(String)
    
    // Backup/Restore Errors
    case backupError(String)
    case restoreError(String)
    
    // User Interaction Errors
    case userCancelled
    case userTimeout(String)
    case userInputError(String)
    
    public var errorDescription: String? {
        switch self {
        case .coreDataError(let message):
            return "Database Error: \(message)"
        case .concurrentModification(let message):
            return "Concurrent Modification Error: \(message)"
        case .migrationError(let message):
            return "Migration Error: \(message)"
        case .persistenceError(let message):
            return "Persistence Error: \(message)"
        case .dataCorruption(let message):
            return "Data Corruption Error: \(message)"
        case .invalidGameState(let message):
            return "Game Error: \(message)"
        case .invalidPlayerState(let message):
            return "Player Error: \(message)"
        case .invalidRoundState(let message):
            return "Round Error: \(message)"
        case .scoreError(let message):
            return "Score Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        case .inputValidation(let message):
            return "Input Validation Error: \(message)"
        case .stateValidation(let message):
            return "State Validation Error: \(message)"
        case .resourceConstraint(let message):
            return "Resource Error: \(message)"
        case .diskSpace(let message):
            return "Disk Space Error: \(message)"
        case .memoryWarning(let message):
            return "Memory Warning: \(message)"
        case .backupError(let message):
            return "Backup Error: \(message)"
        case .restoreError(let message):
            return "Restore Error: \(message)"
        case .userCancelled:
            return "Operation cancelled by user"
        case .userTimeout(let message):
            return "User Timeout: \(message)"
        case .userInputError(let message):
            return "User Input Error: \(message)"
        }
    }
    
    public var recoveryStrategy: RecoveryStrategy {
        switch self {
        case .concurrentModification:
            return .retryWithBackoff(initial: 0.5, multiplier: 2.0, maxAttempts: 3)
        case .coreDataError, .persistenceError:
            return .retry(maxAttempts: 3)
        case .migrationError, .dataCorruption:
            return .rollback
        case .invalidGameState, .invalidPlayerState, .invalidRoundState:
            return .userPrompt(message: "Would you like to return to the main menu?")
        case .scoreError, .validationError, .inputValidation, .stateValidation:
            return .userPrompt(message: "Would you like to try again?")
        case .resourceConstraint, .diskSpace, .memoryWarning:
            return .userPrompt(message: "Please free up some resources and try again")
        case .backupError, .restoreError:
            return .retry(maxAttempts: 2)
        case .userCancelled, .userTimeout, .userInputError:
            return .abort
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .coreDataError:
            return "Try restarting the app or clearing some data"
        case .concurrentModification:
            return "The data was modified by another operation. Please try again"
        case .migrationError:
            return "Try reinstalling the app if the problem persists"
        case .persistenceError:
            return "Check your device's storage and try again"
        case .dataCorruption:
            return "The data may be corrupted. Try restoring from a backup"
        case .invalidGameState:
            return "Return to the main menu and start a new game"
        case .invalidPlayerState:
            return "Try refreshing the player data"
        case .invalidRoundState:
            return "Try returning to the previous round"
        case .scoreError:
            return "Verify the score values and try again"
        case .validationError, .inputValidation:
            return "Check your input and try again"
        case .stateValidation:
            return "The app is in an invalid state. Try restarting"
        case .resourceConstraint:
            return "Close some other apps and try again"
        case .diskSpace:
            return "Free up some storage space and try again"
        case .memoryWarning:
            return "Close some background apps and try again"
        case .backupError:
            return "Ensure you have enough storage space for the backup"
        case .restoreError:
            return "Verify the backup file is not corrupted"
        case .userCancelled:
            return "You can try the operation again when ready"
        case .userTimeout:
            return "The operation timed out. Please try again"
        case .userInputError:
            return "Please check your input and try again"
        }
    }
} 