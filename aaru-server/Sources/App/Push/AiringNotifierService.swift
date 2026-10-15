import Logging
import ServiceLifecycle

/// Runs the airing notifier every ten minutes in the API process.
struct AiringNotifierService: Service {
    let notifier: AiringNotifier
    let logger: Logger
    var interval: Duration = .seconds(600)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    let sent = try await notifier.runOnce()
                    if sent > 0 {
                        logger.info("Airing notifications sent", metadata: ["count": "\(sent)"])
                    }
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Airing notifier pass failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
