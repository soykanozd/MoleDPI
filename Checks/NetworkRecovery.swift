import Foundation

actor RecoveryFixture: ConnectionEngine {
    var starts = 0
    var checks = 0
    var blocked = false
    var fails = false
    var waiting: CheckedContinuation<Void, Never>?
    func block() { blocked = true }
    func fail() { fails = true }
    func release() { blocked = false; waiting?.resume(); waiting = nil }
    func start(targets: [SiteCheck]) -> [SiteCheck] {
        starts += 1
        return targets.map { var site = $0; site.reachable = true; return site }
    }
    func health(targets: [SiteCheck]) async -> [SiteCheck]? {
        checks += 1
        if blocked { await withCheckedContinuation { waiting = $0 } }
        return targets.map { var site = $0; site.reachable = !fails; site.failure = fails ? .dns : nil; return site }
    }
    func stop() {}
}
actor QUICHealthFixture: ConnectionEngine {
    var blocked: Bool
    var waiting: CheckedContinuation<Bool?,Never>?
    init(blocked:Bool = false) { self.blocked = blocked }
    func block() { blocked = true }
    func release() { blocked = false; let value = waiting; waiting = nil; value?.resume(returning:true) }
    func start(targets:[SiteCheck])->[SiteCheck] { targets.map { var item=$0; item.reachable=true; return item } }
    func health(targets:[SiteCheck])->[SiteCheck]? { targets }
    func quicStatus() async -> Bool? {
        if blocked { return await withCheckedContinuation { waiting=$0 } }
        return true
    }
    func stop() { release() }
}
actor DelayRecorder {
    var count=0
    func sleep(_ nanos:UInt64) async throws { count+=1; try await Task.sleep(nanoseconds:nanos) }
}
@main struct NetworkRecoveryTests {
    @MainActor static func main() async throws {
        func expect(_ value: Bool, _ label: String) throws {
            guard value else { throw RoutingError.message(label) }
            print("PASS " + label)
        }
        func eventually(_ condition: () async -> Bool) async throws {
            for _ in 0..<500 {
                if await condition() { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            throw RoutingError.message("Timed out waiting for test event")
        }
        for (code, issue) in [(Int32(6),ConnectionIssue.dns),(28,.timeout),(60,.secureAccess),(22,.remoteResponse),(7,.accessUnverified)] {
            try expect(ConnectionIssue.curlExit(code) == issue, "curl exit category \(code)")
        }
        try expect(ConnectionIssue.curlExit(0) == nil, "successful HTTPS has no failure")
        let quic = QUICHealthFixture(), delay = DelayRecorder()
        let quicModel = Model(engine:quic,monitorNetwork:false,sleep:{ try await delay.sleep($0) })
        quicModel.connect(); await quicModel.task?.value
        try await eventually { await delay.count == 1 }
        await quic.block(); quicModel.refreshHealth()
        try await eventually { await quic.waiting != nil }
        quicModel.networkChanged(false); await quic.release()
        try await eventually { await delay.count >= 2 }
        try expect(quicModel.recovering && quicModel.issueMessage?.contains("No internet") == true,
                   "late QUIC health result cannot erase a newer offline event")
        quicModel.disconnect(); await quicModel.task?.value
        let startupGate = QUICHealthFixture(blocked:true)
        let startup = Model(engine:startupGate,monitorNetwork:false)
        startup.connect()
        try await eventually { await startupGate.waiting != nil }
        startup.networkChanged(false); await startupGate.release(); await startup.task?.value
        try expect(startup.state == .off && startup.recovering,"offline startup cannot publish Connected")
        startup.disconnect(); await startup.task?.value
        let fixture = RecoveryFixture()
        let model = Model(engine:fixture, monitorNetwork:false)
        model.connect(); await model.task?.value
        await fixture.block()
        model.refreshHealth()
        try await eventually { await fixture.waiting != nil }
        model.networkChanged(false)
        await fixture.release()
        try await Task.sleep(nanoseconds:15_000_000)
        try expect(model.recovering && model.issueMessage?.contains("No internet") == true, "old network success cannot overwrite offline state")
        model.reviewConnectionHelp()
        try expect(model.diagnostics?.contains("Wi-Fi") == true, "offline help provides a next step")
        model.networkChanged(true)
        try await eventually { !model.recovering }
        try expect(await fixture.starts == 1, "network return preserves healthy engine")
        let beforeSleep = await fixture.checks
        model.systemWillSleep(); model.refreshHealth()
        try await Task.sleep(nanoseconds:15_000_000)
        try expect(await fixture.checks == beforeSleep, "no health checks during system sleep")
        model.systemDidWake(); model.systemDidWake()
        try await eventually { !model.recovering }
        try expect(await fixture.starts == 1, "repeated wake preserves working engine")
        await fixture.fail()
        // Each immediate refresh must count toward the same failure streak.
        for number in 1...3 {
            let checks = await fixture.checks
            model.refreshHealth()
            try await eventually { await fixture.checks > checks }
            if number < 3 {
                try await eventually { model.recovering }
                try await Task.sleep(nanoseconds:5_000_000)
            }
        }
        try await eventually { model.state == .off }
        model.reviewConnectionHelp()
        try expect(model.diagnostics?.contains("control destination could not be resolved") == true, "DNS evidence selects specific guidance")
        model.reviewDiagnostics()
        try expect(model.diagnostics?.contains("Check category: dns") == true, "sanitized report contains failure category")
        try expect(!model.diagnostics!.contains("discord") && !model.diagnostics!.contains("roblox"), "diagnostics use general wording")
        model.disconnect(); await model.task?.value
        model.systemDidWake(); model.networkChanged(true)
        try await Task.sleep(nanoseconds:15_000_000)
        try expect(await fixture.starts == 1 && !model.wantsConnection, "manual disconnect cancels pending recovery and future wake")
        let asleepEngine = RecoveryFixture()
        let asleep = Model(engine:asleepEngine, monitorNetwork:false)
        asleep.systemWillSleep(); asleep.connect()
        try expect(await asleepEngine.starts == 0, "connect during sleep waits")
        asleep.systemDidWake()
        try await eventually { asleep.state == .on }
        asleep.beginShutdown(); try await asleep.waitForShutdown()
        asleep.systemDidWake(); asleep.networkChanged(true)
        try expect(await asleepEngine.starts == 1 && asleep.quitting, "quit blocks wake and path reconnection")
    }
}
