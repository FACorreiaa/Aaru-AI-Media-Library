import Logging
import ServiceLifecycle

/// Answers queued `@aaru` mentions in the background, one at a time, off the request path.
struct AgentReplyWorker: Service {
    let replies: AgentReplyService
    let logger: Logger
    var idle: Duration = .seconds(1)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    if try await replies.runNext() {
                        continue
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // The job already recorded its failure; the loop must outlive one bad mention.
                    logger.error("Agent reply step failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: idle)
            }
        }
    }
}
