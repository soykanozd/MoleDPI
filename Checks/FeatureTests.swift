import Foundation
@main struct FourTests {
 @MainActor static func main() async throws {
   func expect(_ value:Bool,_ name:String) throws {
     guard value else { throw RoutingError.message(name) }; print("PASS "+name)
   }
   try expect(TCPStrategy.profiles[1].contains("--hostlist-exclude-domains=rbxcdn.com") &&
              TCPStrategy.profiles[1].last == "--split-pos=host+1", "OOB-incompatible CDN uses ordinary splitting")
   try expect(PFConnection.strategyOrder(saved:2)==[2,0,1],"last verified strategy first")
   try expect(PFConnection.strategyOrder(saved:99)==[0,1,2],"invalid stored strategy ignored")
   try expect(ReleaseVersion("v0.10.0-beta")! > ReleaseVersion("v0.9.9-beta")!,"numeric release comparison")
   try expect(ReleaseVersion("v0.9.3")! > ReleaseVersion("v0.9.3-beta")!,"stable supersedes same beta")
   try expect(ReleaseVersion("vbroken")==nil,"invalid version rejected")
   try expect(UpdateChecker.safeURL("https://github.com/soykanozd/MoleDPI/releases/tag/v0.9.4-beta") != nil &&
    UpdateChecker.safeURL("https://github.com.attacker.invalid/soykanozd/MoleDPI/releases/tag/x")==nil,"update URL allowlist")
   for suffix in ["v1.2.1/../evil", "v1.2.1?body=secret", "v1.2.1%2Fextra", "v1.2.1#fragment", "unversioned"] {
    try expect(UpdateChecker.safeURL("https://github.com/soykanozd/MoleDPI/releases/tag/"+suffix)==nil,"noncanonical update link rejected")
   }
   func release(_ tag:String,_ prerelease:Bool=false,_ draft:Bool=false)->[String:Any] {
    ["tag_name":tag,"prerelease":prerelease,"draft":draft,"html_url":"https://github.com/soykanozd/MoleDPI/releases/tag/"+tag]
   }
   let releases=[release("v1.2.1"),release("v2.0.0-beta",true),release("v3.0.0",false,true)]
   try expect(UpdateChecker.newest(in:releases,current:ReleaseVersion("v1.2.0")!)?.lastPathComponent=="v1.2.1","regular app only offers published regular updates")
   try expect(UpdateChecker.newest(in:releases,current:ReleaseVersion("v1.2.0-beta")!)?.lastPathComponent=="v2.0.0-beta","beta app retains beta update channel")
   var mismatch=release("v1.2.1");mismatch["html_url"]="https://github.com/soykanozd/MoleDPI/releases/tag/v9.0.0"
   try expect(UpdateChecker.newest(in:[mismatch],current:ReleaseVersion("v1.2.0")!)==nil,"release metadata must match its link")
   do {
    try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in
     let reply=ServiceReply(c);reply.arm(seconds:0.02)
     DispatchQueue.global().asyncAfter(deadline:.now()+0.04) { reply.finish();reply.finish(RoutingError.message("late")) }
    }
    try expect(false,"missing helper reply must time out")
   } catch { try expect(error.localizedDescription.contains("timed out"),"helper timeout resumes once despite late replies") }
   try expect(FriendlyError.message(HelperApprovalDenied()).contains("Permission"),"permission guidance")
   let secret=FriendlyError.message(RoutingError.message("token=secret /private/fixture 192.0.2.1"))
   try expect(!secret.contains("secret") && !secret.contains("192.0.2.1"),"friendly error excludes raw data")
   let fallback=Model(engine:FallbackFixture(),monitorNetwork:false)
   fallback.connect();await fallback.task?.value
   try expect(fallback.state == .on && fallback.quicActive == false,"verified TCP fallback remains connected")
   fallback.reviewDiagnostics()
   try expect(fallback.diagnostics?.contains("QUIC routing active: false")==true,"report accurately identifies QUIC fallback")
   fallback.disconnect();await fallback.task?.value
   fallback.quicActive=true
   fallback.reviewDiagnostics()
   try expect(fallback.diagnostics?.contains("QUIC routing active: false")==true,"disconnected report cannot claim stale QUIC activity")
   let gate=QUICGateFixture()
   let controlled=Model(engine:gate,monitorNetwork:false)
   var states:[Model.State]=[]
   let observation=controlled.$state.sink { states.append($0) }
   controlled.connect()
   for _ in 0..<500 { if await gate.waiting { break }; try await Task.sleep(nanoseconds:2_000_000) }
   try expect(await gate.waiting,"status retrieval reached cancellation gate")
   controlled.disconnect();await controlled.task?.value
   try expect(controlled.state == .off && !states.contains(.on),"disconnect during QUIC status cannot publish Connected")
   observation.cancel()
   let e=Counting()
   let m=Model(engine:e, monitorNetwork:false, healthInterval:30_000_000_000)
   m.connect(); await m.task?.value
   m.refreshHealth(); m.refreshHealth()
   try await Task.sleep(nanoseconds:20_000_000)
   let checks = await e.checks, starts = await e.starts
   try expect(checks==1 && starts==1,"wake/path refresh coalesced without restart")
   m.disconnect(); await m.task?.value
   m.refreshHealth()
   let finalStarts = await e.starts
   try expect(!m.wantsConnection && finalStarts==1,"refresh cannot reconnect after manual disconnect")
 }
}
actor Counting: ConnectionEngine {
 var starts=0,checks=0
 func start(targets:[SiteCheck])->[SiteCheck] { starts+=1;return targets.map{var s=$0;s.reachable=true;return s} }
 func health(targets:[SiteCheck])->[SiteCheck]? { checks+=1;return targets.map{var s=$0;s.reachable=true;return s} }
 func stop(){}
}

actor FallbackFixture: ConnectionEngine {
 nonisolated let requestsQUIC=true
 func quicStatus()->Bool? { false }
 func start(targets:[SiteCheck])->[SiteCheck] { targets.map{var s=$0;s.reachable=true;return s} }
 func health(targets:[SiteCheck])->[SiteCheck]? { targets }
 func stop(){}
}

actor QUICGateFixture: ConnectionEngine {
 var pending:CheckedContinuation<Bool?,Never>?
 var waiting:Bool { pending != nil }
 func start(targets:[SiteCheck])->[SiteCheck] { targets.map{var s=$0;s.reachable=true;return s} }
 func quicStatus() async -> Bool? { await withCheckedContinuation { pending=$0 } }
 func health(targets:[SiteCheck])->[SiteCheck]? { targets }
 func stop() { let current=pending;pending=nil;current?.resume(returning:false) }
}
