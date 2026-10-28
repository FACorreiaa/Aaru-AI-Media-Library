/// Shared secrets the router checks, from `AppConfig`. Empty turns each one's route or header off.
struct RouterSecrets: Sendable {
    /// `METRICS_SECRET`: the bearer for `/internal/metrics`.
    var metrics = ""
    /// `WEB_CLIENT_SECRET`: lets the web Worker name the visitor behind it (`X-Aaru-Visitor`).
    var webClient = ""
}

extension AppConfig {
    var routerSecrets: RouterSecrets {
        RouterSecrets(metrics: metricsSecret, webClient: webClientSecret)
    }
}
