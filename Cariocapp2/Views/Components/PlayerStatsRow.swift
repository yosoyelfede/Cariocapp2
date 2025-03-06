import SwiftUI

struct PlayerStatsRow: View {
    let player: Player
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(player.name)
                    .font(.headline)
                
                Spacer()
                
                if player.gamesPlayed > 0 {
                    Text("\(Int(player.gamesWon)) wins")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                StatLabel(
                    title: "Games",
                    value: "\(Int(player.gamesPlayed))"
                )
                
                if player.gamesPlayed > 0 {
                    StatLabel(
                        title: "Win Rate",
                        value: String(format: "%.0f%%", player.winRate * 100)
                    )
                    
                    StatLabel(
                        title: "Avg Position",
                        value: String(format: "%.1f", player.averagePosition)
                    )
                    
                    StatLabel(
                        title: "Total Score",
                        value: "\(player.totalScore)"
                    )
                } else {
                    Text("No games played yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
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