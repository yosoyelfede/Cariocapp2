import Foundation
import CryptoKit

/// Types of user input that need validation
enum InputType {
    case playerName
    case score
    case gameId
    case backup
    
    var validationPattern: String {
        switch self {
        case .playerName:
            return "^[a-zA-Z0-9\\s'-]{2,30}$"
        case .score:
            return "^-?\\d{1,4}$"
        case .gameId:
            return "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        case .backup:
            return "^[a-zA-Z0-9_-]+\\.backup$"
        }
    }
    
    var maxLength: Int {
        switch self {
        case .playerName: return 30
        case .score: return 5
        case .gameId: return 36
        case .backup: return 50
        }
    }
}

/// Manager for handling security-related operations
class SecurityManager {
    static let shared = SecurityManager()
    
    private let sanitizationQueue = DispatchQueue(label: "com.cariocapp.security.sanitization")
    private let validationQueue = DispatchQueue(label: "com.cariocapp.security.validation")
    
    private init() {}
    
    /// Sanitize user input
    func sanitizeInput(_ input: String, type: InputType) -> String {
        sanitizationQueue.sync {
            var sanitized = input.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Enforce maximum length
            if sanitized.count > type.maxLength {
                sanitized = String(sanitized.prefix(type.maxLength))
            }
            
            // Remove potentially harmful characters based on input type
            switch type {
            case .playerName:
                sanitized = sanitized.replacingOccurrences(of: "[^a-zA-Z0-9\\s'-]", with: "", options: .regularExpression)
            case .score:
                sanitized = sanitized.replacingOccurrences(of: "[^-0-9]", with: "", options: .regularExpression)
            case .gameId:
                sanitized = sanitized.replacingOccurrences(of: "[^0-9a-fA-F-]", with: "", options: .regularExpression)
            case .backup:
                sanitized = sanitized.replacingOccurrences(of: "[^a-zA-Z0-9_.-]", with: "", options: .regularExpression)
            }
            
            return sanitized
        }
    }
    
    /// Validate user input
    func validateInput(_ input: String, type: InputType) -> Bool {
        validationQueue.sync {
            guard input.count <= type.maxLength else { return false }
            
            let regex = try? NSRegularExpression(pattern: type.validationPattern)
            let range = NSRange(input.startIndex..., in: input)
            return regex?.firstMatch(in: input, range: range) != nil
        }
    }
    
    /// Generate a secure hash for data verification
    func generateHash(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Verify data integrity using a hash
    func verifyDataIntegrity(_ data: Data, hash: String) -> Bool {
        let computedHash = generateHash(for: data)
        return computedHash == hash
    }
    
    /// Secure data for storage
    func secureData(_ data: Data) throws -> Data {
        let key = SymmetricKey(size: .bits256)
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined ?? Data()
    }
    
    /// Validate and sanitize a batch of inputs
    func validateAndSanitizeBatch(_ inputs: [(String, InputType)]) -> [(String, Bool)] {
        return inputs.map { input, type in
            let sanitized = sanitizeInput(input, type: type)
            let isValid = validateInput(sanitized, type: type)
            return (sanitized, isValid)
        }
    }
    
    /// Check if an operation is allowed based on current security context
    func isOperationAllowed(_ operation: String) -> Bool {
        // Add security checks based on operation type
        switch operation {
        case "deleteGame":
            return true // Add actual security logic
        case "modifyPlayer":
            return true // Add actual security logic
        case "exportData":
            return true // Add actual security logic
        default:
            return false
        }
    }
    
    /// Log security-related events
    func logSecurityEvent(_ event: String, severity: SecurityEventSeverity) {
        let timestamp = Date()
        let logEntry = SecurityLogEntry(timestamp: timestamp,
                                      event: event,
                                      severity: severity)
        // Add actual logging logic
        print("🔒 Security Event: \(logEntry)")
    }
}

/// Severity levels for security events
enum SecurityEventSeverity {
    case info
    case warning
    case error
    case critical
}

/// Structure for security log entries
struct SecurityLogEntry {
    let timestamp: Date
    let event: String
    let severity: SecurityEventSeverity
} 