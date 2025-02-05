import SwiftUI

struct PlayerStatsRow: View {
    let player: Player
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(player.name)
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(player.gamesWon)) wins")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                StatLabel(
                    title: "Games",
                    value: "\(Int(player.gamesPlayed))"
                )
                
                StatLabel(
                    title: "Win Rate",
                    value: String(format: "%.0f%%", player.winRate * 100)
                )
                
                StatLabel(
                    title: "Avg Score",
                    value: String(format: "%.1f", Double(player.totalScore) / Double(max(1, player.gamesPlayed)))
                )
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct StatLabel: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }
} 