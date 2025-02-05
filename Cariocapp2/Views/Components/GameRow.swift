import SwiftUI
import CoreData

struct GameRow: View {
    let game: Game
    
    // MARK: - Formatters
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    // MARK: - Computed Properties
    private var playerNames: String {
        game.playersArray.map { $0.name }.joined(separator: ", ")
    }
    
    private var roundInfo: String {
        "Round \(game.currentRound) of \(game.maxRounds)"
    }
    
    private var winningPlayer: Player? {
        guard !game.isActive else { return nil }
        return game.playersArray.min { $0.totalScore < $1.totalScore }
    }
    
    private var gameStatus: String {
        game.isActive ? "In Progress" : "Completed"
    }
    
    private var accessibilityLabel: String {
        let status = game.isActive ? "Active game" : "Completed game"
        let winner = winningPlayer.map { ", Winner: \($0.name)" } ?? ""
        return "\(status), \(playerNames), \(roundInfo)\(winner)"
    }
    
    // MARK: - View Body
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(game.isActive ? "Round \(game.currentRound)" : "Completed")
                    .font(.headline)
                
                Spacer()
                
                Text(game.startDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(game.playersArray.map { $0.name }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(game.isActive ? .updatesFrequently : .isStaticText)
    }
}

// MARK: - Preview Provider
#Preview("Game Row", traits: .sizeThatFitsLayout) {
    let previewContainer = PersistenceController.preview
    let context = previewContainer.container.viewContext
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    
    let game = try! Game.createPreviewGame(in: context)
    try! context.save()
    
    return GameRow(game: game)
        .padding()
        .environment(\.managedObjectContext, context)
        .environmentObject(DependencyContainer(persistenceController: previewContainer))
} 