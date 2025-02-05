import SwiftUI

// MARK: - Score Row View
struct PlayerScoreRow: View {
    let player: Player
    let currentRoundScore: Int32?  // Score from current round
    let totalScore: Int32          // Total score across all rounds
    let isDealer: Bool
    
    var body: some View {
        HStack {
            // Player name and dealer indicator
            HStack(spacing: 8) {
                if isDealer {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                        .imageScale(.small)
                }
                Text(player.name)
                    .font(.headline)
            }
            .layoutPriority(1)
            
            Spacer()
            
            // Scores
            HStack(spacing: 16) {
                if let roundScore = currentRoundScore {
                    Text("\(roundScore)")
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Text("\(totalScore)")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .layoutPriority(1)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// Make the view equatable to prevent unnecessary updates
extension PlayerScoreRow: Equatable {
    static func == (lhs: PlayerScoreRow, rhs: PlayerScoreRow) -> Bool {
        lhs.player.id == rhs.player.id &&
        lhs.currentRoundScore == rhs.currentRoundScore &&
        lhs.totalScore == rhs.totalScore &&
        lhs.isDealer == rhs.isDealer
    }
} 