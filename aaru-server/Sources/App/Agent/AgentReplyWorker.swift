import Logging
import ServiceLifecycle

/// Answers queued `@aaru` mentions in the background, off the request path. `workers` loops
/// (`AGENT_REPLY_WORKERS`, default 1) share the leased queue.
struct AgentReplyWorker: Service {
    let replies: AgentReplyService
    let logger: Logger
    var workers = 1
    var idle: Duration = .seconds(1)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            await workerLoops(max(1, workers), idle: idle) {
                try await replies.runNext()
            } failed: { error in
                // The job already recorded its failure; the loop must outlive one bad mention.
                logger.error("Agent reply step failed", metadata: ["error": "\(error)"])
            }
        }
    }
}
