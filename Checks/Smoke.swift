// SPDX-License-Identifier: GPL-3.0-only
import Foundation
actor TestEngine: ConnectionEngine {
    let proxy = Proxy()
    func start(targets: [SiteCheck]) async throws -> [SiteCheck] {
        try Task.checkCancellation(); try await proxy.start()
        do { try Task.checkCancellation() } catch { proxy.stop(); throw error }
        return await PFConnection.checks(targets, transport: .http)
    }
    func health(targets: [SiteCheck]) async -> [SiteCheck]? { await PFConnection.checks(targets, transport: .http) }
    func stop() { proxy.stop() }
}
actor DeniedEngine: ConnectionEngine {
    func start(targets: [SiteCheck]) throws -> [SiteCheck] { throw RoutingError.message("Test: ağ izni reddedildi") }
    func health(targets: [SiteCheck]) -> [SiteCheck]? { nil }
    func stop() { }
}
actor UnrestorableEngine: ConnectionEngine {
    func start(targets: [SiteCheck]) throws -> [SiteCheck] { throw RoutingError.message("not used") }
    func health(targets: [SiteCheck]) -> [SiteCheck]? { nil }
    func stop() throws { throw RoutingError.message("Test: geri alma başarısız") }
}
actor RecoverOnRetry: ConnectionEngine {
    private(set) var starts = 0
    private(set) var stops = 0
    func start(targets: [SiteCheck]) throws -> [SiteCheck] {
        starts += 1; return targets
    }
    func health(targets: [SiteCheck]) -> [SiteCheck]? { nil }
    func stop() throws {
        stops += 1
        if stops == 1 { throw RoutingError.message("Recovery needed") }
    }
}
@main struct Smoke {
    @MainActor static func main() async throws {
        func expect(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: message, code: 1) }
        }
        try expect(Request.host(Data("CONNECT discord.com:443 HTTP/1.1\r\n\r\n".utf8)) == "discord.com", "valid CONNECT")
        for bad in ["GET / HTTP/1.1\r\n\r\n", "CONNECT a.com:80 HTTP/1.1\r\n\r\n", "CONNECT a@b.com:443 HTTP/1.1\r\n\r\n", "CONNECT :443 HTTP/1.1\r\n\r\n", "CONNECT a.com:443 HTTP/1.1\r\n"] {
            try expect(Request.host(Data(bad.utf8)) == nil, "reject malformed / unsupported request")
        }
        print("PASS: CONNECT parser and restrictions")
        let body = Data([1, 0, 0, 20]) + Data("discord.com".utf8)
        let original = Data([22, 3, 1, 0, UInt8(body.count)]) + body + Data([20, 3, 3, 0, 1, 1])
        let (fragmented, at) = TLSFragment.split(original, host: "discord.com")!
        let recovered = Data(fragmented[5..<at]) + Data(fragmented[(at + 5)..<(original.count + 5 - 6)])
        try expect(recovered == body, "TLS handshake bytes must be preserved")
        try expect(fragmented.suffix(6) == original.suffix(6), "following record preserved")
        try expect(TLSFragment.split(Data(original.prefix(7)), host: "discord.com") == nil, "incomplete TLS rejected")
        print("PASS: TLS record split preserves handshake and following record")
        let current: [String: Any] = ["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 18080, "HTTPEnable": 1, "HTTPProxy": "other"]
        try expect(SystemRouting.owns(current), "recognize only own proxy")
        let restored = SystemRouting.restored(current: current, saved: ["HTTPSEnable": 0, "HTTPSProxy": "prior", "HTTPSPort": 8080])
        try expect((restored["HTTPSEnable"] as? Int) == 0 && restored["HTTPProxy"] as? String == "other" && restored["HTTPSProxy"] as? String == "prior", "restore only owned fields and preserve unrelated settings")
        print("PASS: proxy ownership and selective restoration (pure data, no system changes)")
        let denied = Model(engine: DeniedEngine())
        denied.connect()
        let failureDeadline = Date().addingTimeInterval(5)
        while denied.state == .digging && Date() < failureDeadline { try await Task.sleep(nanoseconds: 50_000_000) }
        try expect(denied.state == .off && denied.detail.contains("reddedildi"), "authorization failure never displays connected")
        try expect(!denied.showDetails, "connection failure must not open settings")
        let unrestorable = Model(engine: UnrestorableEngine())
        var quitAllowed = false; var quitRejected = false
        unrestorable.disconnect(completion: { quitAllowed = true }, failure: { quitRejected = true })
        let restoreDeadline = Date().addingTimeInterval(5)
        while unrestorable.state == .emerging && Date() < restoreDeadline { try await Task.sleep(nanoseconds: 50_000_000) }
        try expect(unrestorable.recoveryNeeded && quitRejected && !quitAllowed, "restoration failure must prevent normal quit and expose recovery")
        try expect(!unrestorable.showDetails, "restoration failure must not open settings")
        print("PASS: permission failure stays disconnected; restoration failure prevents quit; settings remain user-controlled")
        let recoveringEngine = RecoverOnRetry()
        let quitting = Model(engine: recoveringEngine)
        quitting.beginShutdown()
        quitting.beginShutdown()
        quitting.connect()
        var refused = false
        do { try await quitting.waitForShutdown() } catch { refused = true }
        try expect(refused, "unverified cleanup must refuse termination")
        quitting.beginShutdown()
        try await quitting.waitForShutdown()
        let starts = await recoveringEngine.starts
        let stops = await recoveringEngine.stops
        try expect(starts == 0 && stops == 2, "quit admission lock, single cleanup and retry")
        print("PASS: repeated quit shares cleanup; connect blocked; failed shutdown can be retried")
        let a = Proxy(); let b = Proxy()
        try await a.start()
        try expect(ListenerReadiness.ownsTCPListener(pid: getpid(), port: 18080), "recognizes the listener owned by this process")
        try expect(!ListenerReadiness.ownsTCPListener(pid: getppid(), port: 18080), "rejects a listener owned by another process")
        var rejected = false
        do { try await b.start() } catch { rejected = true }
        b.stop()
        try expect(rejected, "port collision must fail")
        a.stop(); try await a.start(); a.stop()
        print("PASS: port conflict, stop, restart")
        if ProcessInfo.processInfo.environment["MOLE_LIVE_TEST"] == "1" {
            try await a.start()
            let ok = await Probe.check(host: "example.com", proxy: true)
            a.stop()
            try expect(ok, "real HTTPS through split proxy")
            let stopped = await Probe.check(host: "example.com", proxy: true)
            try expect(!stopped, "stopped proxy must not silently fall back")
            print("PASS: certificate-verified HTTPS via proxy; disconnect blocks proxy")
            try await a.start()
            for host in ["discord.com", "www.roblox.com"] {
                async let direct = Probe.check(host: host, proxy: false)
                async let proxied = Probe.check(host: host, proxy: true)
                print("OBSERVATION: \(host) direct=\(await direct) proxy=\(await proxied)")
            }
            a.stop()
            let model = Model(engine: TestEngine(), sites: [SiteCheck(host: "example.com", name: "Web")])
            let start = Date(); model.connect()
            try expect(model.state == .digging, "starts digging")
            while model.state == .digging && Date().timeIntervalSince(start) < 15 { try await Task.sleep(nanoseconds: 100_000_000) }
            try expect(model.state == .on && model.sites.allSatisfy({ $0.reachable == true }), "connected requires a successful real probe")
            model.disconnect()
            try expect(model.state == .emerging, "reverse animation starts after proxy stops")
            let closed = await Probe.check(host: "example.com", proxy: true)
            try expect(!closed, "disconnect closes data path immediately")
            let reverseDeadline = Date().addingTimeInterval(5)
            while model.state == .emerging && Date() < reverseDeadline { try await Task.sleep(nanoseconds: 100_000_000) }
            try expect(model.state == .off, "reverse animation ends off: \(model.state)")
            model.connect(); model.disconnect()
            let cancelDeadline = Date().addingTimeInterval(5)
            while model.state == .emerging && Date() < cancelDeadline { try await Task.sleep(nanoseconds: 100_000_000) }
            try expect(model.state == .off, "cancellation never becomes connected")
            let afterCancel = await Probe.check(host: "example.com", proxy: true)
            try expect(!afterCancel, "cancel must not leave listener behind")
            print("PASS: real connectivity gate, reverse state, cancellation")
        } else { print("SKIP: external HTTPS (MOLE_LIVE_TEST=1 to enable)") }
    }
}
