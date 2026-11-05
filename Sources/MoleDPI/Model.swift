// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import Network

@MainActor final class Model: ObservableObject {
    enum State { case off, digging, on, emerging }
    @Published var state: State = .off
    @Published var detail = "The mole is still above ground."
    @Published var sites: [SiteCheck]
    @Published var showDetails = false
    @Published var showMode = false
    @Published var recoveryNeeded = false
    @Published private(set) var quitting = false
    @Published private(set) var wantsConnection = false
    @Published private(set) var recovering = false
    private var reconnectTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var networkAvailable = true
    private var activity: NSObjectProtocol?
    private func holdConnectionActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Maintain the requested MoleDPI session")
    }
    private func releaseConnectionActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
    private var attempt = 0
    private let healthInterval: UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void
    @Published var quitError: String?
    private var shutdownTask: Task<Void, Never>?
    private var shutdownResult: Result<Void, Error>?
    private let engine: any ConnectionEngine
    var task: Task<Void, Never>?
    var monitor: Task<Void, Never>?
    private var stopped: [() -> Void] = []
    private var failed: [() -> Void] = []
    init(engine: any ConnectionEngine = PFConnection(), sites: [SiteCheck] = [
        SiteCheck(host: "example.com", name: "Web"),
        SiteCheck(host: "discord.com", name: "Discord web"),
        SiteCheck(host: "www.roblox.com", name: "Roblox web")
    ], monitorNetwork: Bool = true, healthInterval: UInt64 = 30_000_000_000,
         sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.engine = engine; self.sites = sites; self.healthInterval = healthInterval; self.sleep = sleep
        if monitorNetwork {
            let path = NWPathMonitor(); pathMonitor = path
            path.pathUpdateHandler = { [weak self] value in
                let available = value.status == .satisfied
                Task { @MainActor [weak self] in self?.networkChanged(available) }
            }
            path.start(queue: DispatchQueue(label: "MoleDPI.network-path"))
        }
    }
    deinit { pathMonitor?.cancel() }
    func networkChanged(_ available: Bool) {
        networkAvailable = available
        guard wantsConnection, !quitting else { return }
        if !available { recovering = true }
        else if state == .off { scheduleRecovery() }
    }
    private func scheduleRecovery() {
        guard wantsConnection, !quitting, reconnectTask == nil else { return }
        recovering = true
        let pending = task, health = monitor
        reconnectTask = Task {
            await pending?.value; await health?.value
            while wantsConnection && !quitting && !Task.isCancelled {
                do { try await engine.stop(); recoveryNeeded = false; break }
                catch {
                    recoveryNeeded = true
                    do { try await sleep(30_000_000_000) } catch { reconnectTask = nil; return }
                }
            }
            guard wantsConnection, !quitting, !Task.isCancelled else { reconnectTask = nil; return }
            state = .off
            guard networkAvailable else { reconnectTask = nil; return }
            let seconds = min(30, 1 << min(attempt, 5))
            attempt += 1
            do { try await sleep(UInt64(seconds) * 1_000_000_000) }
            catch { reconnectTask = nil; return }
            reconnectTask = nil
            guard wantsConnection, !quitting, networkAvailable else { return }
            connect()
        }
    }
    func connect() {
        guard !quitting, reconnectTask == nil, state == .off, !recoveryNeeded else { return }
        wantsConnection = true
        holdConnectionActivity()
        if !networkAvailable { recovering = true; return }
        let timing = ConnectClock()
        timing.mark("ui.connect")
        sites = sites.map { SiteCheck(host: $0.host, name: $0.name) }
        state = .digging; detail = "The mole is digging underground."
        timing.mark("ui.digging")
        task = Task {
            do {
                guard !Task.isCancelled else { return }
                let checked = try await engine.start(targets: sites)
                guard !Task.isCancelled else { return }
                sites = checked
                guard !checked.isEmpty, checked.allSatisfy({ $0.reachable == true }) else {
                    throw RoutingError.message("Connection could not be verified.")
                }
                state = .on; detail = "The mole is underground. Tunnel ready!"
                timing.mark("ui.connected")
                recovering = false; attempt = 0
                monitor = Task {
                    var completeFailures = 0
                    while !Task.isCancelled && wantsConnection && !quitting {
                        do { try await sleep(healthInterval) } catch { return }
                        guard !Task.isCancelled, wantsConnection, !quitting else { return }
                        guard networkAvailable else { recovering = true; continue }
                        let results = await engine.health(targets: sites)
                        guard !Task.isCancelled, wantsConnection, !quitting else { return }
                        guard let results else { scheduleRecovery(); return }
                        sites = results
                        // A single remote endpoint failure does not prove the
                        // worker or the user's established connections are dead.
                        if results.contains(where: { $0.reachable == true }) {
                            completeFailures = 0; recovering = false
                        } else {
                            recovering = true; completeFailures += 1
                            if completeFailures >= 3 { scheduleRecovery(); return }
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                do { try await engine.stop() } catch { recoveryNeeded = true }
                state = .off; detail = error.localizedDescription
                if error is HelperApprovalDenied { wantsConnection = false; recovering = false; releaseConnectionActivity() }
                else { scheduleRecovery() }
            }
        }
    }
    // Lock admission synchronously, including before the first panel opening.
    func beginShutdown() {
        wantsConnection = false
        releaseConnectionActivity()
        reconnectTask?.cancel()
        quitting = true
        quitError = nil
        guard shutdownTask == nil else { return }
        shutdownResult = nil
        let pending = task
        let health = monitor
        let recovery = reconnectTask
        if state != .emerging { pending?.cancel() }
        health?.cancel()
        shutdownTask = Task {
            // Join owned work before releasing its resources. A concurrent
            // disconnect is allowed to finish its original restoration.
            await pending?.value
            await health?.value
            await recovery?.value
            do {
                try await engine.shutdown()
                shutdownResult = .success(())
            } catch { shutdownResult = .failure(error) }
        }
    }
    func waitForShutdown() async throws {
        let deadline = DispatchTime.now() + .seconds(20)
        while shutdownResult == nil && DispatchTime.now() < deadline {
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        guard let result = shutdownResult else {
            // Retain the outstanding task. Retry joins it instead of starting
            // a competing repair while the previous one is still in flight.
            throw RoutingError.message("Cleanup is still pending. Try quitting again.")
        }
        shutdownTask = nil
        try result.get()
    }
    func disconnect(reason: String? = nil, completion: (() -> Void)? = nil, failure: (() -> Void)? = nil) {
        guard !quitting else { return }
        wantsConnection = false; recovering = false
        releaseConnectionActivity()
        let recovery = reconnectTask
        recovery?.cancel()
        if let completion { stopped.append(completion) }; if let failure { failed.append(failure) }
        guard state != .emerging else { return }
        let previous = task
        let previousMonitor = monitor
        previous?.cancel(); previousMonitor?.cancel()
        state = .emerging; detail = "The mole is returning above ground."
        task = Task {
            do {
                try await engine.stop()
                await previous?.value; await previousMonitor?.value; await recovery?.value
                reconnectTask = nil
                recoveryNeeded = false
                guard !Task.isCancelled else { return }
                state = .off; detail = reason ?? "The mole is still above ground."
                let callbacks = stopped; stopped.removeAll(); failed.removeAll(); callbacks.forEach { $0() }
            } catch {
                recoveryNeeded = true; state = .off; detail = error.localizedDescription
                let callbacks = failed; stopped.removeAll(); failed.removeAll(); callbacks.forEach { $0() }
            }
        }
    }
}
