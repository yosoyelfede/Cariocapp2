import SwiftUI

struct PlayerSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let registeredPlayers: [Player]
    @Binding var selectedPlayers: Set<Player>
    let maxSelectable: Int
    
    init(registeredPlayers: [Player], selectedPlayers: Binding<Set<Player>>, maxSelectable: Int) {
        print("🎮 PlayerSelectionSheet - Initializing")
        print("🎮 Registered players count: \(registeredPlayers.count)")
        print("🎮 Registered players: \(registeredPlayers.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
        self.registeredPlayers = registeredPlayers
        self._selectedPlayers = selectedPlayers
        self.maxSelectable = maxSelectable
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if registeredPlayers.isEmpty {
                    ContentUnavailableView(
                        "No Players Available",
                        systemImage: "person.2.slash",
                        description: Text("Add players in the Players tab first")
                    )
                    .padding()
                } else {
                    TableView(
                        items: registeredPlayers,
                        columns: [
                            TableColumn("Name") { player in
                                player.name
                            },
                            TableColumn("Status") { player in
                                selectedPlayers.contains(player) ? "Selected" : ""
                            }
                        ]
                    )
                    .onTapGesture { location in
                        // Handle selection through tap gesture
                        if let player = hitTest(location, in: registeredPlayers) {
                            withAnimation {
                                if selectedPlayers.contains(player) {
                                    selectedPlayers.remove(player)
                                } else if selectedPlayers.count < maxSelectable {
                                    selectedPlayers.insert(player)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                print("🎮 PlayerSelectionSheet appeared")
                print("🎮 View context: \(viewContext)")
                print("🎮 Available players: \(registeredPlayers.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
                print("🎮 Selected players: \(selectedPlayers.map { "\($0.name) (\($0.id))" }.joined(separator: ", "))")
            }
        }
    }
    
    private func hitTest(_ location: CGPoint, in players: [Player]) -> Player? {
        // Implement hit testing logic here
        // This is a placeholder - you'll need to implement proper hit testing
        return nil
    }
} 