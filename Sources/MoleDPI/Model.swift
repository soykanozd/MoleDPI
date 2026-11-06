// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import Network
import AppKit

@MainActor final class Model: ObservableObject {
    enum State { case off, digging, on, emerging }
    @Published var state: State = .off
    @Published var detail = "The mole is still above ground."
    @Published var sites: [SiteCheck]
    @Published var showDetails = false
    @Published var quicActive: Bool?
    @Published var diagnostics: String?
    @Published var reportTitle = "Diagnostics"
    private var lastIssue: ConnectionIssue?
    private var networkRevision: UInt64 = 0
    private var sleeping = false
    private var completeFailures = 0
    private var sleepObserver: NSObjectProtocol?
    @Published var showMode = false
    @Published var recoveryNeeded = false
    @Published private(set) var quitting = false
    @Published private(set) var wantsConnection = false
    @Published private(set) var recovering = false
    let updates = UpdateChecker()
    @Published var issueMessage: String?
    private var wakeObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
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
        SiteCheck(host: "example.com", name: "HTTPS check 1"),
        SiteCheck(host: "discord.com", name: "HTTPS check 2"),
        SiteCheck(host: "www.roblox.com", name: "HTTPS check 3")
    ], monitorNetwork: Bool = true, healthInterval: UInt64 = 30_000_000_000,
         sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.engine = engine; self.sites = sites; self.healthInterval = healthInterval; self.sleep = sleep
        if monitorNetwork {
            let path = NWPathMonitor(); pathMonitor = path
            path.pathUpdateHandler = { [weak self] value in
                let available = value.status == .satisfied
                Task { @MainActor [weak self] in self?.networkChanged(available) }
            }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.systemDidWake() }
            }
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.systemWillSleep() }
            }
            path.start(queue: DispatchQueue(label: "MoleDPI.network-path"))
        }
    }
    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        pathMonitor?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    func systemWillSleep() {
        sleeping = true
        networkRevision &+= 1
        monitor?.cancel()
        if wantsConnection { recovering = true; issueMessage = "Waiting for the Mac to wake." }
    }
    func systemDidWake() {
        sleeping = false
        networkRevision &+= 1
        guard wantsConnection, !quitting else { return }
        if state == .on { refreshHealth() }
        else if state == .off { scheduleRecovery() }
    }
    func refreshHealth() {
        guard wantsConnection, !quitting, !sleeping, state == .on, reconnectTask == nil, refreshTask == nil else { return }
        let old = monitor
        old?.cancel()
        refreshTask = Task {
            await old?.value
            guard wantsConnection, !quitting, !sleeping, !Task.isCancelled, reconnectTask == nil, state == .on else { refreshTask = nil; return }
            startMonitoring(immediate: true)
            refreshTask = nil
        }
    }
    func networkChanged(_ available: Bool) {
        networkRevision &+= 1
        networkAvailable = available
        guard wantsConnection, !quitting else { return }
        if !available {
            recovering = true
            lastIssue = .offline
            issueMessage = ConnectionIssue.offline.message
        } else if state == .off { scheduleRecovery() }
        else if state == .on { refreshHealth() }
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
            guard networkAvailable, !sleeping else { reconnectTask = nil; return }
            let seconds = min(30, 1 << min(attempt, 5))
            attempt += 1
            do { try await sleep(UInt64(seconds) * 1_000_000_000) }
            catch { reconnectTask = nil; return }
            reconnectTask = nil
            guard wantsConnection, !quitting, networkAvailable, !sleeping else { return }
            connect()
        }
    }
    func reviewConnectionHelp() {
        reportTitle = "Connection Help"
        let issue = lastIssue ?? (networkAvailable ? nil : .offline)
        let summary = issue.map { "Last observed issue\n" + $0.message + "\n\n" + $0.guidance } ?? "No specific failure has been recorded.\n\nIf access stops, check your internet connection and any network sign-in page. Retry Connect, or try another network. Failed access checks alone cannot identify censorship."
        diagnostics = summary + "\n\nThese checks cover a few HTTPS destinations, not every website or application. TCP ports 80/443 are supported. Experimental QUIC processing covers UDP/443; other UDP uses the normal system path. ISP bypass is not guaranteed. Your public IP remains visible.\n\nNothing is uploaded automatically."
    }
    func reviewDiagnostics() {
        reportTitle = "Diagnostics"
        // Allowlist only; raw errors and system dictionaries are excluded.
        diagnostics = [
            "MoleDPI experimental diagnostics",
            "Version: " + (Bundle.main.object(forInfoDictionaryKey:"MoleReleaseTag") as? String ?? "source-build"),
            "macOS: " + [ProcessInfo.processInfo.operatingSystemVersion.majorVersion, ProcessInfo.processInfo.operatingSystemVersion.minorVersion, ProcessInfo.processInfo.operatingSystemVersion.patchVersion].map(String.init).joined(separator:"."),
            "Check category: " + (lastIssue?.rawValue ?? "none"),
            "State: " + String(describing: state),
            "Connection requested: " + String(wantsConnection),
            "UDP/443 configured: " + String(engine.requestsQUIC),
            "QUIC routing active: " + (state == .on ? (quicActive.map(String.init) ?? "not verified") : (state == .off && !recoveryNeeded ? "false" : "not verified")),
            "Recovering: " + String(recovering),
            "Cleanup required: " + String(recoveryNeeded),
            "Verified targets: " + String(sites.filter { $0.reachable == true }.count) + "/" + String(sites.count),
            "Recovery DNS transport: HTTPS (when activated)",
            "No IP addresses, paths, browsing history or raw errors included."
        ].joined(separator: "\n")
    }
    func connect() {
        guard !quitting, reconnectTask == nil, state == .off, !recoveryNeeded else { return }
        wantsConnection = true
        holdConnectionActivity()
        if !networkAvailable || sleeping { recovering = true; return }
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
                quicActive = await engine.quicStatus()
                guard !Task.isCancelled, wantsConnection, !quitting, state == .digging else { return }
                guard !checked.isEmpty, checked.allSatisfy({ $0.reachable == true }) else {
                    throw RoutingError.message("Connection could not be verified.")
                }
                state = .on; detail = "The mole is underground. Tunnel ready!"
                timing.mark("ui.connected")
                recovering = false; attempt = 0; completeFailures = 0; lastIssue = nil
                issueMessage = nil
                startMonitoring()
            } catch {
                guard !Task.isCancelled else { return }
                do { try await engine.stop() } catch { recoveryNeeded = true }
                state = .off; lastIssue = error as? ConnectionIssue; detail = FriendlyError.message(error); issueMessage = detail
                if error is HelperApprovalDenied { wantsConnection = false; recovering = false; releaseConnectionActivity() }
                else { scheduleRecovery() }
            }
        }
    }
    private func startMonitoring(immediate: Bool = false) {
        monitor = Task {
        var checkNow = immediate
        while !Task.isCancelled && wantsConnection && !quitting {
            if !checkNow {
                do { try await sleep(healthInterval) } catch { return }
            }
            checkNow = false
            guard !Task.isCancelled, wantsConnection, !quitting else { return }
            guard networkAvailable, !sleeping else { recovering = true; continue }
            let revision = networkRevision
            let results = await engine.health(targets: sites)
            guard !Task.isCancelled, wantsConnection, !quitting else { return }
            guard revision == networkRevision, !sleeping, networkAvailable else { continue }
            guard let results else { lastIssue = .localEngine; issueMessage = "The network engine stopped. Reconnecting."; scheduleRecovery(); return }
            sites = results
            quicActive = await engine.quicStatus()
            guard !Task.isCancelled, wantsConnection, !quitting else { return }
            // A single remote endpoint failure does not prove the
            // worker or the user's established connections are dead.
            if results.contains(where: { $0.reachable == true }) {
                completeFailures = 0; recovering = false; issueMessage = nil; lastIssue = nil
            } else {
                lastIssue = ConnectionIssue.summarize(results)
                recovering = true; issueMessage = lastIssue?.message; completeFailures += 1
                if completeFailures >= 3 { scheduleRecovery(); return }
            }
        }
        }
    }
    // Lock admission synchronously, including before the first panel opening.
    func beginShutdown() {
        wantsConnection = false
        updates.cancel(); refreshTask?.cancel(); pathMonitor?.cancel()
        releaseConnectionActivity()
        reconnectTask?.cancel()
        quitting = true
        quitError = nil
        guard shutdownTask == nil else { return }
        shutdownResult = nil
        let pending = task
        let health = monitor
        let recovery = reconnectTask
        let refresh = refreshTask
        if state != .emerging { pending?.cancel() }
        health?.cancel()
        shutdownTask = Task {
            // Join owned work before releasing its resources. A concurrent
            // disconnect is allowed to finish its original restoration.
            await pending?.value
            await health?.value
            await recovery?.value
            await refresh?.value
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
        issueMessage = nil
        let refresh = refreshTask; refresh?.cancel()
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
                await previous?.value; await previousMonitor?.value; await recovery?.value; await refresh?.value
                reconnectTask = nil
                recoveryNeeded = false
                guard !Task.isCancelled else { return }
                state = .off; detail = reason ?? "The mole is still above ground."
                let callbacks = stopped; stopped.removeAll(); failed.removeAll(); callbacks.forEach { $0() }
            } catch {
                recoveryNeeded = true; state = .off; lastIssue = error as? ConnectionIssue; detail = FriendlyError.message(error); issueMessage = detail
                let callbacks = failed; stopped.removeAll(); failed.removeAll(); callbacks.forEach { $0() }
            }
        }
    }
}
