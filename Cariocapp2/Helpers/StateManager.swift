import Foundation
import CoreData
import Combine
import SwiftUI

/// Custom navigation state that can be encoded/decoded
struct NavigationState: Codable {
    var path: [String] = []
    
    func toNavigationPath() -> NavigationPath {
        var navPath = NavigationPath()
        path.forEach { navPath.append($0) }
        return navPath
    }
    
    static func from(_ navigationPath: NavigationPath) -> NavigationState {
        var paths: [String] = []
        if let representation = navigationPath.codable {
            let mirror = Mirror(reflecting: representation)
            if let elements = mirror.children.first?.value as? [Any] {
                for element in elements {
                    if let path = element as? String {
                        paths.append(path)
                    }
                }
            }
        }
        return NavigationState(path: paths)
    }
}

/// Represents the current state of the application
@MainActor
final class AppState: ObservableObject {
    // MARK: - Constants
    private struct Constants {
        static let maxHistoryItems = 10
        static let stateKey = "AppState"
        static let navigationKey = "NavigationState"
        static let autosaveInterval: TimeInterval = 30
    }
    
    // MARK: - Types
    enum StateError: LocalizedError {
        case invalidState(String)
        case restorationFailed(String)
        case serializationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidState(let message):
                return "Invalid state: \(message)"
            case .restorationFailed(let message):
                return "State restoration failed: \(message)"
            case .serializationFailed(let message):
                return "State serialization failed: \(message)"
            }
        }
    }
    
    // MARK: - Error Types
    enum AppError: LocalizedError {
        case invalidState(String)
        case restorationFailed(String)
        case serializationFailed(String)
        case stateSaveFailed(String)
        case stateRestorationFailed(String)
        case memoryWarning(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidState(let message):
                return "Invalid state: \(message)"
            case .restorationFailed(let message):
                return "State restoration failed: \(message)"
            case .serializationFailed(let message):
                return "State serialization failed: \(message)"
            case .stateSaveFailed(let message):
                return "Failed to save state: \(message)"
            case .stateRestorationFailed(let message):
                return "Failed to restore state: \(message)"
            case .memoryWarning(let message):
                return "Memory warning: \(message)"
            }
        }
    }
    
    // MARK: - Properties
    private let viewContext: NSManagedObjectContext
    
    @Published private(set) var currentGame: Game?
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var navigationPath = NavigationPath()
    @Published private(set) var resourceState = AppResourceState()
    
    private var cancellables = Set<AnyCancellable>()
    private let stateQueue = DispatchQueue(label: "com.cariocapp.state", qos: .userInitiated)
    private var stateHistory: [StateSnapshot] = []
    private var autosaveTimer: Timer?
    
    // MARK: - Initialization
    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        setupObservers()
        setupAutosave()
    }
    
    // MARK: - State Management
    func updateGame(_ game: Game?) async throws {
        await MainActor.run {
            saveCurrentState()
            withAnimation {
                self.currentGame = game
            }
        }
        try await saveApplicationState()
    }
    
    func setLoading(_ loading: Bool) {
        Task { @MainActor in
            withAnimation {
                self.isLoading = loading
            }
        }
    }
    
    func setError(_ error: AppError?) {
        Task { @MainActor in
            withAnimation {
                self.error = error
            }
        }
    }
    
    // MARK: - Navigation
    func navigate(to destination: any Hashable) async throws {
        await MainActor.run {
            withAnimation {
                navigationPath.append(destination)
            }
        }
        try await saveApplicationState()
    }
    
    func navigateBack() async throws {
        await MainActor.run {
            withAnimation {
                navigationPath.removeLast()
            }
        }
        try await saveApplicationState()
    }
    
    func updateNavigationPath(_ path: NavigationPath) async throws {
        await MainActor.run {
            withAnimation {
                navigationPath = path
            }
        }
        try await saveApplicationState()
    }
    
    // MARK: - State History
    private func saveCurrentState() {
        let snapshot = StateSnapshot(
            gameId: currentGame?.id,
            navigationState: NavigationState.from(navigationPath),
            timestamp: Date()
        )
        stateHistory.append(snapshot)
        
        if stateHistory.count > Constants.maxHistoryItems {
            stateHistory.removeFirst()
        }
    }
    
    func restoreLastState() async throws {
        guard let lastState = stateHistory.popLast() else {
            throw StateError.restorationFailed("No previous state available")
        }
        
        if let gameId = lastState.gameId {
            let request = NSFetchRequest<Game>(entityName: "Game")
            request.predicate = NSPredicate(format: "id == %@", gameId as CVarArg)
            
            let game = try viewContext.fetch(request).first
            try await updateGame(game)
        }
        
        await MainActor.run {
            withAnimation {
                self.navigationPath = lastState.navigationState.toNavigationPath()
            }
        }
        
        try await saveApplicationState()
    }
    
    // MARK: - Resource Management
    func updateResourceState() async {
        let newState = await AppResourceState.current()
        await MainActor.run {
            self.resourceState = newState
        }
    }
    
    // MARK: - State Persistence
    func saveApplicationState() async throws {
        let state = ApplicationState(
            navigationState: NavigationState.from(navigationPath),
            currentGameId: currentGame?.id
        )
        
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(state)
                    UserDefaults.standard.set(data, forKey: Constants.stateKey)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: StateError.serializationFailed(error.localizedDescription))
                }
            }
        }
    }
    
    func restoreApplicationState() async throws {
        guard let data = UserDefaults.standard.data(forKey: Constants.stateKey) else {
            return
        }
        
        let decoder = JSONDecoder()
        let state = try decoder.decode(ApplicationState.self, from: data)
        
        if let gameId = state.currentGameId {
            let request = NSFetchRequest<Game>(entityName: "Game")
            request.predicate = NSPredicate(format: "id == %@", gameId as CVarArg)
            
            if let game = try viewContext.fetch(request).first {
                try await updateGame(game)
            }
        }
        
        await MainActor.run {
            withAnimation {
                self.navigationPath = state.navigationState.toNavigationPath()
            }
        }
    }
    
    private func saveState() async {
        print("📱 AppState - Saving state")
        do {
            try await saveApplicationState()
            print("📱 AppState - State saved successfully")
        } catch {
            print("❌ AppState - Failed to save state: \(error)")
            setError(AppError.stateSaveFailed(error.localizedDescription))
        }
    }
    
    public func restoreState() async {
        print("📱 AppState - Restoring state")
        do {
            try await restoreApplicationState()
            print("📱 AppState - State restored successfully")
        } catch {
            print("❌ AppState - Failed to restore state: \(error)")
            setError(AppError.stateRestorationFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Observers
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.saveState()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.restoreState()
            }
        }
    }
    
    private func setupAutosave() {
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: Constants.autosaveInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                do {
                    try await self.saveApplicationState()
                } catch {
                    self.setError(AppError.stateSaveFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func handleMemoryWarning() {
        let currentState = resourceState // Capture current state locally
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.updateResourceState()
            if self.resourceState.isMemoryConstrained {
                self.setError(AppError.memoryWarning("Application is running low on memory"))
            }
        }
    }
    
    // MARK: - Cleanup
    @MainActor
    func cleanup() async {
        // Clear state
        currentGame = nil
        isLoading = false
        error = nil
        navigationPath = NavigationPath()
        resourceState = AppResourceState()
        stateHistory.removeAll()
        
        // Remove observers
        cancellables.removeAll()
        
        // Stop autosave
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        
        // Clear persisted state
        UserDefaults.standard.removeObject(forKey: Constants.stateKey)
        UserDefaults.standard.removeObject(forKey: Constants.navigationKey)
    }
    
    deinit {
        // Perform synchronous cleanup
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        cancellables.removeAll()
        
        // Schedule async cleanup without capturing self
        let stateKey = Constants.stateKey
        let navigationKey = Constants.navigationKey
        Task { @MainActor in
            UserDefaults.standard.removeObject(forKey: stateKey)
            UserDefaults.standard.removeObject(forKey: navigationKey)
        }
    }
}

// MARK: - Supporting Types
struct StateSnapshot {
    let gameId: UUID?
    let navigationState: NavigationState
    let timestamp: Date
}

struct ApplicationState: Codable {
    let navigationState: NavigationState
    let currentGameId: UUID?
}

struct AppResourceState {
    var isMemoryConstrained: Bool = false
    var isDiskSpaceConstrained: Bool = false
    var availableMemory: UInt64 = 0
    var availableDiskSpace: UInt64 = 0
    
    static func current() async -> AppResourceState {
        var state = AppResourceState()
        
        // Get memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            state.availableMemory = info.resident_size
            state.isMemoryConstrained = info.resident_size > 500_000_000 // 500MB threshold
        }
        
        // Get disk space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            if let freeSize = attrs[.systemFreeSize] as? NSNumber {
                state.availableDiskSpace = freeSize.uint64Value
                state.isDiskSpaceConstrained = freeSize.uint64Value < 100_000_000 // 100MB threshold
            }
        }
        
        return state
    }
} 