import Foundation
import os.log

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cariocapp"
    
    static let game = os.Logger(subsystem: subsystem, category: "game")
    static let player = os.Logger(subsystem: subsystem, category: "player")
    static let coreData = os.Logger(subsystem: subsystem, category: "coreData")
    static let ui = os.Logger(subsystem: subsystem, category: "ui")
    
    static func logError(_ error: Error, category: os.Logger) {
        category.error("\(error.localizedDescription)")
    }
    
    static func logGameEvent(_ message: String) {
        game.info("\(message)")
    }
    
    static func logPlayerEvent(_ message: String) {
        player.info("\(message)")
    }
    
    static func logDataEvent(_ message: String) {
        coreData.info("\(message)")
    }
    
    static func logUIEvent(_ message: String) {
        ui.info("\(message)")
    }
    
    static func logDebug(_ message: String, category: os.Logger) {
        category.debug("\(message)")
    }
    
    #if DEBUG
    static func debugOnly(_ message: String) {
        print("DEBUG: \(message)")
    }
    #endif
} 