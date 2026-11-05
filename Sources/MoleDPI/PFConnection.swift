// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin
import SystemConfiguration

// Opt-in diagnostics. Labels are static; only monotonic durations are emitted.
struct ConnectClock {
    private let start = DispatchTime.now().uptimeNanoseconds
    static let enabled = ProcessInfo.processInfo.environment["MOLEDPI_TIMING"] == "1"
    func mark(_ stage: String) {
        guard Self.enabled else { return }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        print(String(format: "TIMING %@ %.2f ms", stage, ms))
        fflush(stdout)
    }
}
struct SiteCheck: Identifiable, Sendable {
    let host: String
    let name: String
    var reachable: Bool?
    var direct: Bool?
    var failure: ConnectionIssue?
    var id: String { host }
}
protocol ConnectionEngine: Sendable {
    func start(targets: [SiteCheck]) async throws -> [SiteCheck]
    func health(targets: [SiteCheck]) async -> [SiteCheck]?
    func stop() async throws
    func shutdown() async throws
}
extension ConnectionEngine {
    func shutdown() async throws { try await stop() }
}
// Manages a source-built tpws probe and an ephemeral privileged PF session.
// All process ownership and session state are serialized by this actor.
actor PFConnection: ConnectionEngine {
    static let profiles = [
        ["--split-pos=host+1", "--tlsrec=host+1"],
        ["--split-pos=2", "--oob=tls"],
        ["--split-pos=host+1", "--tlsrec=host+1"]
    ]
    static func strategyOrder(saved: Int? = UserDefaults.standard.object(forKey: "MoleDPI.verifiedStrategy.v1") as? Int) -> [Int] {
        guard let saved, profiles.indices.contains(saved) else { return Array(profiles.indices) }
        return [saved] + profiles.indices.filter { $0 != saved }
    }
    private let requireDNSRecovery: Bool
    init(requireDNSRecovery: Bool = false) { self.requireDNSRecovery = requireDNSRecovery }
    private var generation = UUID()
    private var exitSignal: DispatchSemaphore?
    private var preflight: Process?
    private var service: NSXPCConnection?
    private var heartbeatTask: Task<Void, Never>?
    private var heartbeatURL: URL?
    private var statusURL: URL?
    private var dnsRelay: DNSRelay?
    private var activeProfile: Int?

    static func resource(_ name: String) throws -> URL {
        if let dir = Bundle.main.resourceURL {
            let path = dir.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path.path) { return path }
        }
        // Source-only tests can point to their own locally built resources.
        if let directory = ProcessInfo.processInfo.environment["MOLE_NATIVE_DIR"] {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path.path) { return path }
        }
        throw RoutingError.message("The bundled network engine is missing. Reinstall MoleDPI.")
    }
    static func checks(_ targets: [SiteCheck], transport: Probe.Transport, addresses: [String:String] = [:]) async -> [SiteCheck] {
        await withTaskGroup(of: SiteCheck.self) { group in
            for target in targets {
                group.addTask {
                    var result = target
                    result.failure = await Probe.failure(host: target.host, using: transport, address: addresses[target.host])
                    result.reachable = result.failure == nil
                    return result
                }
            }
            var map: [String: SiteCheck] = [:]
            for await result in group { map[result.host] = result }
            return targets.compactMap { map[$0.host] }
        }
    }
    private func valid(_ id: UUID) throws {
        guard id == generation, !Task.isCancelled else { throw CancellationError() }
    }
    private func readStatus() -> [String: Any]? {
        guard let statusURL, let data = try? Data(contentsOf: statusURL), data.count < 32768 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    private func stopPreflight() {
        guard let process = preflight else { return }
        if process.isRunning {
            process.terminate()
            // waitUntilExit can leave a cooperative executor parked in a run loop
            // after the child has already exited. Observe termination directly.
            _ = exitSignal?.wait(timeout: .now() + 2)
        }
        if !process.isRunning || (kill(process.processIdentifier, 0) == -1 && errno == ESRCH) {
            preflight = nil; exitSignal = nil
        }
    }
    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    private func startPrivileged(profile: Int, id: UUID) async throws {
        let launch = ConnectClock()
        let server = try await ServiceClient.prepare()
        launch.mark("helper.identity-and-setup")
        try valid(id)
        let session = UUID().uuidString
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MoleDPI/Sessions/\(session)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let heartbeat = dir.appendingPathComponent("alive")
        try Data(session.utf8).write(to: heartbeat, options: .atomic)
        heartbeatURL = heartbeat
        statusURL = URL(fileURLWithPath: "/var/run/moledpi/\(session)/status.json")
        heartbeatTask = Task.detached {
            while !Task.isCancelled {
                try? Data(session.utf8).write(to: heartbeat, options: .atomic)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        let connection = ServiceClient.connect(serverHash: server)
        service = connection
        do { try await ServiceClient.request(connection, session: session, profile: profile) }
        catch let rejection as WorkerStartRejected {
            // Authenticated explicit refusal means no worker for this UUID ran.
            if generation == id { statusURL = nil }
            throw rejection
        }
        launch.mark("helper.xpc-started")
        try valid(id)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            try valid(id)
            if let status = readStatus(), let phase = status["phase"] as? String {
                if phase == "active" {
                    if ConnectClock.enabled {
                        for label in ["launch", "listen", "apply"] {
                            if let ms = status[label] as? NSNumber { print("TIMING worker.\(label) \(ms) ms") }
                        }
                    }
                    launch.mark("helper.pf-ready"); activeProfile = profile; return
                }
                if phase == "failed" || phase == "cleanup_failed" { throw RoutingError.message(status["message"] as? String ?? "Could not start the PF session.") }
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw RoutingError.message("Network session startup timed out.")
    }
    func start(targets: [SiteCheck]) async throws -> [SiteCheck] {
        guard !targets.isEmpty else { throw RoutingError.message("No connectivity targets are configured.") }
        let clock = ConnectClock()
        let id = UUID(); generation = id
        do {
            try valid(id)
            if FileManager.default.fileExists(atPath: SystemRouting.journalURL.path) { try await SystemRouting().restore() }
            clock.mark("engine.legacy-restore-check")
            async let directChecks: [SiteCheck] = {
                let results = await Self.checks(targets, transport: .direct)
                clock.mark("engine.direct-https-done")
                return results
            }()
            try valid(id)
            let binary = try Self.resource("tpws")
            var selected: Int?
            var alternate: [String:String] = [:]
            var lastResults = targets
            if requireDNSRecovery {
                for site in targets {
                    alternate[site.host] = await Probe.alternateAddress(site.host)
                }
                let relay = DNSRelay(); dnsRelay = relay
                try await relay.start(); try valid(id)
            }
            for (orderIndex, profile) in Self.strategyOrder().enumerated() {
                try valid(id)
                let process = Process(); process.executableURL = binary
                process.arguments = ["--socks", "--bind-addr=127.0.0.1", "--port=18081", "--maxconn=128", "--filter-tcp=80,443", "--filter-l7=http,tls"] + Self.profiles[profile]
                process.environment = ["PATH": "/usr/bin:/bin", "MOLEDPI_SPLIT_DELAY_US": profile == 2 ? "20000" : "0"]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                guard preflight == nil else { throw RoutingError.message("The previous network probe is still stopping.") }
                let done = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in done.signal() }
                try process.run()
                clock.mark("engine.probe-started")
                preflight = process; exitSignal = done
                let readyDeadline = DispatchTime.now() + .seconds(2)
                while !ListenerReadiness.ownsTCPListener(pid: process.processIdentifier, port: 18081) {
                    try valid(id)
                    guard process.isRunning, DispatchTime.now() < readyDeadline else {
                        throw RoutingError.message("Local strategy probe did not open its TCP port.")
                    }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                try valid(id)
                guard process.isRunning else { stopPreflight(); throw RoutingError.message("Could not start the probe. Port 18081 may be busy.") }
                clock.mark("engine.probe-readiness-gate")
                var results = await Self.checks(targets, transport: .socks, addresses: alternate)
                if alternate.isEmpty, orderIndex == 0, results.contains(where: { $0.reachable != true }) {
                    for site in results where site.reachable != true {
                        alternate[site.host] = await Probe.alternateAddress(site.host)
                    }
                    try valid(id)
                    if !alternate.isEmpty {
                        let relay = DNSRelay()
                        dnsRelay = relay
                        try await relay.start()
                        try valid(id)
                    }
                    if !alternate.isEmpty { results = await Self.checks(targets, transport: .socks, addresses: alternate) }
                }
                try valid(id)
                // Check process identity/liveness as well as real HTTPS; never
                // mistake an unrelated listener's successful request for ours.
                clock.mark("engine.socks-https-done")
                lastResults = results
                let running = process.isRunning
                stopPreflight()
                guard preflight == nil else { throw RoutingError.message("Network probe did not stop.") }
                if running && results.allSatisfy({ $0.reachable == true }) { selected = profile + (alternate.isEmpty ? 0 : 3); break }
            }
            guard let profile = selected else { throw ConnectionIssue.summarize(lastResults) }
            try valid(id)
            clock.mark("engine.preflight-done")
            let baseline = await directChecks // Direct measurements must finish before installing PF rules.
            try valid(id)
            try await startPrivileged(profile: profile, id: id)
            try valid(id)
            clock.mark("engine.pf-ready")
            // curl explicitly ignores application proxies: these requests must
            // succeed through the active PF session, not a diagnostic SOCKS port.
            var results = await Self.checks(targets, transport: .direct)
            try valid(id)
            let failed = results.filter { $0.reachable != true }
            if !failed.isEmpty && readStatus()?["phase"] as? String == "active" {
                clock.mark("engine.pf-https-retry")
                let retried = await Self.checks(failed, transport: .direct)
                try valid(id)
                let byID = Dictionary(uniqueKeysWithValues: retried.map { ($0.id, $0) })
                results = results.map { byID[$0.id] ?? $0 }
            }
            clock.mark("engine.pf-https-done")
            let counterDeadline = Date().addingTimeInterval(4)
            while (readStatus()?["packets"] as? NSNumber)?.uint64Value == 0 && Date() < counterDeadline {
                try valid(id); try await Task.sleep(nanoseconds: 150_000_000)
            }
            guard (readStatus()?["packets"] as? NSNumber)?.uint64Value ?? 0 > 0, results.allSatisfy({ $0.reachable == true }), readStatus()?["phase"] as? String == "active", service != nil else {
                throw results.allSatisfy({ $0.reachable == true }) ? ConnectionIssue.localEngine : ConnectionIssue.summarize(results)
            }
            UserDefaults.standard.set(profile % 3, forKey: "MoleDPI.verifiedStrategy.v1")
            clock.mark("engine.counter-verified")
            return results.enumerated().map { i, site in var result = site; result.direct = baseline[i].reachable; return result }
        } catch {
            stopPreflight()
            // Keep the original error unless cleanup itself needs attention.
            if id == generation { try await stop() }
            throw error
        }
    }
    func sessionStatusForTesting() -> URL? { statusURL }
    private func workerIsHealthy() -> Bool {
        guard service != nil, let status = readStatus(), status["phase"] as? String == "active",
              let checked = status["checkedAt"] as? Double else { return false }
        return Date().timeIntervalSince1970 - checked < 10
    }
    func health(targets: [SiteCheck]) async -> [SiteCheck]? {
        guard workerIsHealthy() else { return nil }
        let results = await Self.checks(targets, transport: .direct)
        guard workerIsHealthy() else { return nil }
        return results
    }
    private func repair() async throws {
        guard let session = statusURL?.deletingLastPathComponent().lastPathComponent, UUID(uuidString: session) != nil else { throw RoutingError.message("The PF recovery session was not found.") }
        guard let service else { throw RoutingError.message("Network helper is unavailable for recovery.") }
        try await ServiceClient.request(service, session: session, profile: nil)
        guard readStatus()?["phase"] as? String == "stopped" else { throw RoutingError.message("Network recovery was not verified.") }

    }
    func stop() async throws {
        generation = UUID(); stopPreflight()
        heartbeatTask?.cancel(); await heartbeatTask?.value; heartbeatTask = nil
        if let heartbeatURL { try? FileManager.default.removeItem(at: heartbeatURL) }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let phase = readStatus()?["phase"] as? String {
                if phase == "stopped" || phase == "failed" { break }
                if phase == "cleanup_failed" { try await repair(); break }
            }
            if statusURL == nil || (service == nil && readStatus() == nil) { break }
            // Cleanup must still yield when called by a cancelled startup task.
            await Task.detached { try? await Task.sleep(nanoseconds: 150_000_000) }.value
        }
        if statusURL != nil {
            if let phase = readStatus()?["phase"] as? String, ["active", "starting", "cleanup_failed"].contains(phase) {
                // The daemon refuses repair while any session worker is running.
                try await repair()
            }
            guard let journal = readStatus(), let phase = journal["phase"] as? String,
                  ["stopped", "failed"].contains(phase), journal["pfToken"] == nil else {
                throw RoutingError.message("Could not verify network cleanup. Retry before quitting.")
            }
        }
        guard preflight == nil else { throw RoutingError.message("The local network probe is still stopping.") }
        dnsRelay?.stop(); dnsRelay = nil
        service?.invalidate(); service = nil
        if let dir = heartbeatURL?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: dir) }
        heartbeatURL = nil; statusURL = nil; activeProfile = nil
    }
    func shutdown() async throws {
        try await stop()
        if FileManager.default.fileExists(atPath: SystemRouting.journalURL.path) {
            try await SystemRouting().restore()
        }
    }
}
