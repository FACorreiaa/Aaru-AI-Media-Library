import CoreLocation

/// "Use my location" (MUS-003): one approximate fix, when in use, then nothing. The Info.plist
/// asks for reduced accuracy by default (`NSLocationDefaultAccuracyReduced`), so the system
/// never offers precise location; the fix is rounded to two decimals and kept only in memory.
enum ApproximateLocation {
    enum Failure: Error {
        case denied, unavailable
    }

    /// The first fix, or a failure after `timeout`. Location stops as soon as this returns.
    @MainActor
    static func current(timeout: Duration = .seconds(20)) async throws -> ConcertPoint {
        #if os(iOS)
            let session = CLServiceSession(authorization: .whenInUse)
            defer { session.invalidate() }
        #else
            // The Mac has no service sessions: ask the classic way, and hold the manager until done.
            let manager = CLLocationManager()
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            defer { withExtendedLifetime(manager) {} }
        #endif
        return try await withThrowingTaskGroup(of: ConcertPoint.self) { group in
            group.addTask { try await firstFix() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.unavailable
            }
            defer { group.cancelAll() }
            guard let point = try await group.next() else { throw Failure.unavailable }
            return point
        }
    }

    private static func firstFix() async throws -> ConcertPoint {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let coordinate = update.location?.coordinate {
                return ConcertPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw Failure.denied
            }
        }
        throw Failure.unavailable
    }
}
