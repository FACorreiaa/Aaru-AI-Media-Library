import Logging
import ServiceLifecycle

/// JOB-001: the in-process import worker. One loop, leased jobs, so a crash mid-job leaves the
/// job re-runnable once its lease expires. `ARCHITECTURE.md` allows one binary until imports
/// block request latency.
struct ImportWorker: Service {
    let imports: ImportService
    let logger: Logger
    var idle: Duration = .seconds(2)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    if try await imports.runNext() {
                        continue
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // The job already recorded its failure; the loop must outlive one bad job.
                    logger.error("Import worker step failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: idle)
            }
        }
    }
}
