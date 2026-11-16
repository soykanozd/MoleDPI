// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

// Cancellation acts on this Process object only. Locking covers the interval
// between checking for cancellation and actually spawning the child.
final class OwnedCommand: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false
    init(_ process: Process) { self.process = process }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                launch(continuation)
            }
        } onCancel: { self.cancel() }
    }
    private func launch(_ done: CheckedContinuation<Void, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { done.resume(throwing: CancellationError()); return }
        process.terminationHandler = { _ in done.resume() }
        do { try process.run() }
        catch { process.terminationHandler = nil; done.resume(throwing: error) }
    }
    private func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+2) { [weak self] in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                if self.cancelled && self.process.isRunning { kill(self.process.processIdentifier,SIGKILL) }
            }
        }
    }
}
