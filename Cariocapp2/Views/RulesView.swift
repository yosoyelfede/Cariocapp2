import SwiftUI

struct RulesView: View {
    private let rounds = RoundRule.allRounds
    
    var body: some View {
        List {
            gameOverviewSection
            gamePlaySection
            roundsSection
            scoringSection
        }
        .navigationTitle("Rules")
    }
    
    private var gameOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Game Overview")
                    .font(.headline)
                
                Text("Carioca is a rummy-style card game where players aim to form specific combinations of cards in each round. The game consists of 8 rounds, with optional rounds that can be included for more variety.")
                    .foregroundColor(.secondary)
                
                Text("Basic Rules")
                    .font(.headline)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint(text: "Players: 2-4 players")
                    BulletPoint(text: "Cards: Two standard 52-card decks with jokers")
                    BulletPoint(text: "Deal: 12 cards per player")
                    BulletPoint(text: "Turn order: Clockwise")
                    BulletPoint(text: "Dealer rotates: After each round")
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var gamePlaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Game Play")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint(text: "On your turn, draw a card from the deck or pick up the top discard")
                    BulletPoint(text: "Form the required combinations for the round")
                    BulletPoint(text: "Discard one card to end your turn")
                    BulletPoint(text: "First player to complete the round's combination and go out wins")
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var roundsSection: some View {
        Section("Rounds") {
            ForEach(rounds) { round in
                RoundRuleRow(rule: round)
            }
        }
    }
    
    private var scoringSection: some View {
        Section("Scoring") {
            VStack(alignment: .leading, spacing: 8) {
                BulletPoint(text: "The first player to complete the round's combinations and go out wins")
                BulletPoint(text: "The winner gets 0 points")
                BulletPoint(text: "Other players get points based on their remaining cards")
                BulletPoint(text: "Lower scores are better")
            }
            .padding(.vertical, 4)
        }
    }
}

struct RoundRuleRow: View {
    let rule: RoundRule
    
    private var isSpecialRound: Bool {
        ["Escala Sucia", "Escala Color", "Escala Bicolor", "Escala Real"].contains(rule.name)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.name)
                    .font(.headline)
                
                if rule.isOptional {
                    Text("Optional")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
            }
            
            if isSpecialRound && !rule.description.isEmpty {
                Text(rule.description)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct RulesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RulesView()
        }
    }
} 