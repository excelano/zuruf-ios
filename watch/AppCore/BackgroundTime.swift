// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

enum BackgroundTime {
    @MainActor
    static func keep<T>(reason: String,
                        _ work: @MainActor () async throws -> T,
                        expired: @escaping @MainActor @Sendable () -> Void) async rethrows -> T {
        let hold = Hold()
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { didExpire in
            if didExpire {
                hold.release()
                Task { @MainActor in expired() }
            } else {
                hold.wait()
            }
        }
        defer { hold.release() }
        return try await work()
    }

    private final class Hold: Sendable {
        private let semaphore = DispatchSemaphore(value: 0)

        func wait() {
            semaphore.wait()
        }

        func release() {
            semaphore.signal()
        }
    }
}
