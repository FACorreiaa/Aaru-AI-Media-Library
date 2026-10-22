import Logging
import ServiceLifecycle

/// JOB-001: the in-process import worker. Leased jobs, so a crash mid-job leaves the job
/// re-runnable once its lease expires. `ARCHITECTURE.md` allows one binary until imports block
/// request latency. `workers` loops (`IMPORTS_WORKERS`, default 1) share the queue.
struct ImportWorker: Service {
    let imports: ImportService
    let logger: Logger
    var workers = 1
    var idle: Duration = .seconds(2)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            await workerLoops(max(1, workers), idle: idle) {
                try await imports.runNext()
            } failed: { error in
                // The job already recorded its failure; the loop must outlive one bad job.
                logger.error("Import worker step failed", metadata: ["error": "\(error)"])
            }
        }
    }
}

/// `count` copies of one queue's loop, each taking the next job until the task is cancelled.
/// `step` returns whether it did work; an idle loop sleeps `idle` before asking again.
func workerLoops(
    _ count: Int,
    idle: Duration = .seconds(2),
    step: @escaping @Sendable () async throws -> Bool,
    failed: @escaping @Sendable (any Error) -> Void
) async {
    await withDiscardingTaskGroup { group in
        for _ in 0 ..< count {
            group.addTask {
                while !Task.isCancelled {
                    do {
                        if try await step() {
                            continue
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        failed(error)
                    }
                    try? await Task.sleep(for: idle)
                }
            }
        }
    }
}
