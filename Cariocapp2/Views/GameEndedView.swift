import SwiftUI
import CoreData

// MARK: - Main View
struct GameEndedView: View {
    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    
    // MARK: - Properties
    let gameID: UUID
    
    // MARK: - State
    @State private var isErrorPresented = false
    @State private var error: Error?
    @State private var isLoading = false
    
    // MARK: - View Body
    var body: some View {
        Group {
            if navigationCoordinator.getGame(id: gameID) != nil {
                mainContent
            } else {
                notFoundContent
            }
        }
        .navigationBarBackButtonHidden()
        .alert("Error", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {
                navigationCoordinator.popToRoot()
            }
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }
    
    // MARK: - View Components
    private var mainContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Game Ended")
                .font(.title)
                .bold()
            
            Text("The game has been saved and you can check the statistics in the main menu.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            returnButton
        }
        .padding()
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
    }
    
    private var notFoundContent: some View {
        ContentUnavailableView(
            "Game Not Found",
            systemImage: "exclamationmark.triangle",
            description: Text("The game may have been deleted")
        )
        .onAppear {
            navigationCoordinator.popToRoot()
        }
    }
    
    private var returnButton: some View {
        Button(action: handleGameEnd) {
            Text("Return to Main Menu")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
        }
        .padding(.horizontal)
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            ProgressView("Loading...")
                .padding()
                .background(.regularMaterial)
                .cornerRadius(8)
        }
    }
    
    // MARK: - Actions
    private func handleGameEnd() {
        Task {
            do {
                try await navigationCoordinator.completeGame(gameID)
            } catch let gameError {
                self.error = gameError
                isErrorPresented = true
            }
        }
    }
}

// MARK: - Preview
struct GameEndedView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let coordinator = NavigationCoordinator(viewContext: context)
        
        if let game = try? Game.createPreviewGame(in: context) {
            NavigationStack {
                GameEndedView(gameID: game.id)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(coordinator)
            }
        }
    }
} 