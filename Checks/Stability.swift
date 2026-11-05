import Foundation
actor Clock {
    var waiters: [CheckedContinuation<Void, Never>] = []
    func sleep(_ ns: UInt64) async throws {
        try Task.checkCancellation()
        // Short test ticks are independent of production backoff durations.
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}
actor Engine: ConnectionEngine {
    var starts = 0
    var stops = 0
    var checks = 0
    var dead = false
    var failed = false
    var allFailed = false
    var once = false
    func start(targets: [SiteCheck]) -> [SiteCheck] {
        starts += 1; dead = false
        return targets.map { var s = $0; s.reachable = true; return s }
    }
    func health(targets: [SiteCheck]) -> [SiteCheck]? {
        checks += 1
        if dead { return nil }
        let transient = once; once = false
        return targets.enumerated().map { i,s in var s=s; s.reachable = !transient && !allFailed && !(failed && i==0); return s }
    }
    func stop() { stops += 1 }
    func failOnce() { once = true }
    func failAll() { allFailed = true }
    func failOne() { failed = true }
    func crash() { dead = true }
}
@main struct Stability {
    @MainActor static func main() async throws {
        func expect(_ yes: Bool,_ text: String) throws {
            guard yes else { throw RoutingError.message(text) }
            print("PASS " + text)
        }
        let e = Engine(), clock = Clock()
        let m = Model(engine:e, monitorNetwork:false, healthInterval:1,
                      sleep:{ try await clock.sleep($0) })
        m.connect(); await m.task?.value
        await e.failOnce()
        try await Task.sleep(nanoseconds:15_000_000)
        try expect(await e.starts == 1 && m.state == .on, "one complete health-check failure does not restart")
        await e.failOne()
        try await Task.sleep(nanoseconds:20_000_000)
        try expect(await e.starts == 1 && m.state == .on,"one endpoint failure leaves the running engine intact")
        m.showDetails = true; m.showDetails = false
        try expect(m.wantsConnection && m.state == .on,"view state does not own connectivity")
        m.networkChanged(false)
        let before = await e.starts
        try await Task.sleep(nanoseconds:10_000_000)
        try expect(await e.starts == before,"offline path does not restart live engine")
        m.networkChanged(true)
        await e.crash()
        try await Task.sleep(nanoseconds:35_000_000)
        try expect(await e.starts == before+1 && m.state == .on,"engine death causes one controlled recovery")
        m.disconnect(); await m.task?.value
        let stopped = await e.starts
        try await Task.sleep(nanoseconds:15_000_000)
        try expect(await e.starts == stopped && !m.wantsConnection && m.state == .off,"manual disconnect prevents late reconnection")
        m.connect(); await m.task?.value
        await e.crash()
        try await Task.sleep(nanoseconds:3_000_000)
        m.beginShutdown(); try await m.waitForShutdown()
        let quit = await e.starts
        try await Task.sleep(nanoseconds:10_000_000)
        try expect(await e.starts == quit && m.quitting && !m.wantsConnection,"quit cancels recovery and blocks reconnect")
        let offlineEngine = Engine()
        let offline = Model(engine: offlineEngine, monitorNetwork:false, healthInterval:1, sleep:{ try await clock.sleep($0) })
        offline.networkChanged(false); offline.connect()
        try expect(await offlineEngine.starts == 0 && offline.wantsConnection, "offline startup waits without starting a worker")
        offline.networkChanged(true)
        try await Task.sleep(nanoseconds:15_000_000)
        try expect(await offlineEngine.starts == 1 && offline.state == .on, "network return restores desired session")
        offline.disconnect(); await offline.task?.value

    }
}
