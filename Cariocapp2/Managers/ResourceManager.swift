import Foundation
import os.log
import UIKit

@MainActor
final class ResourceManager: ObservableObject {
    // MARK: - Constants
    private static let warningMemoryThreshold: UInt64 = 500_000_000  // 500MB
    private static let criticalMemoryThreshold: UInt64 = 800_000_000 // 800MB
    private static let warningDiskThreshold: UInt64 = 100_000_000    // 100MB
    private static let criticalDiskThreshold: UInt64 = 50_000_000    // 50MB
    private static let cleanupInterval: TimeInterval = 300           // 5 minutes
    
    // MARK: - Properties
    private let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.fedelopez.Cariocapp2", category: "ResourceManager")
    @Published private(set) var state: SystemResourceState = .init()
    private var checkTask: Task<Void, Error>?
    private var cleanupTimer: Timer?
    private var memoryWarningObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    init() {
        setupObservers()
        setupCleanupTimer()
    }
    
    // MARK: - Public Interface
    func checkResources() async throws {
        // Cancel any existing check task
        checkTask?.cancel()
        
        // Create new check task
        let task = Task<Void, Error> { @MainActor in
            do {
                // Check memory usage
                let memoryStatus = try await checkMemoryUsage()
                if !Task.isCancelled {
                    state.memoryStatus = memoryStatus
                }
                
                // Check disk space
                let diskStatus = try await checkDiskSpace()
                if !Task.isCancelled {
                    state.diskStatus = diskStatus
                }
                
                // Throw error if resources are critical
                if state.memoryStatus == .critical {
                    throw ResourceError.insufficientMemory(await getMemoryUsage())
                }
                if state.diskStatus == .critical {
                    throw ResourceError.insufficientDisk(await getDiskSpace())
                }
                
                logger.info("Resource check completed successfully")
            } catch {
                logger.error("Resource check failed: \(error.localizedDescription)")
                throw error
            }
        }
        
        checkTask = task
        try await task.value
    }
    
    // MARK: - Resource Checking
    private func checkMemoryUsage() async throws -> ResourceStatus {
        let memoryUsed = await getMemoryUsage()
        
        if memoryUsed >= Self.criticalMemoryThreshold {
            return .critical
        } else if memoryUsed >= Self.warningMemoryThreshold {
            return .low
        } else {
            return .available
        }
    }
    
    private func checkDiskSpace() async throws -> ResourceStatus {
        let freeSpace = await getDiskSpace()
        
        if freeSpace <= Self.criticalDiskThreshold {
            return .critical
        } else if freeSpace <= Self.warningDiskThreshold {
            return .low
        } else {
            return .available
        }
    }
    
    private func getMemoryUsage() async -> UInt64 {
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
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
    
    private func getDiskSpace() async -> UInt64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return (attrs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        } catch {
            logger.error("Error checking disk space: \(error.localizedDescription)")
            return 0
        }
    }
    
    // MARK: - Cleanup
    private func setupObservers() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await self?.handleMemoryWarning()
            }
        }
    }
    
    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: Self.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                try? await self?.performCleanup()
            }
        }
    }
    
    private func handleMemoryWarning() async throws {
        try await performCleanup()
        try await checkResources()
    }
    
    private func performCleanup() async throws {
        // Implement cleanup logic here
        logger.info("Performing resource cleanup")
    }
    
    deinit {
        cleanupTimer?.invalidate()
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        checkTask?.cancel()
    }
}

// MARK: - Supporting Types
struct SystemResourceState {
    var memoryStatus: ResourceStatus = .unknown
    var diskStatus: ResourceStatus = .unknown
}

enum ResourceStatus {
    case unknown
    case available
    case low
    case critical
}

enum ResourceError: LocalizedError {
    case insufficientMemory(UInt64)
    case insufficientDisk(UInt64)
    case cleanupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientMemory(let available):
            return "Insufficient memory: \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)) available"
        case .insufficientDisk(let available):
            return "Insufficient disk space: \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)) available"
        case .cleanupFailed(let message):
            return "Cleanup failed: \(message)"
        }
    }
} 