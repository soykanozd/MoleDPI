// SPDX-License-Identifier: GPL-3.0-only
// Opt-in end-to-end test. Displays a macOS administrator authorization dialog.
import Foundation
import SystemConfiguration
@main struct PFLive {
    static func main() async {
        let originalPF = try! Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf"))
        let originalProxies = SCDynamicStoreCopyProxies(nil)! as NSDictionary
        let engine = PFConnection()
        let sites = [SiteCheck(host: "example.com", name: "Web"), SiteCheck(host: "discord.com", name: "Discord"), SiteCheck(host: "www.roblox.com", name: "Roblox web")]
        do {
            let results = try await engine.start(targets: sites)
            for site in results { print("PF LIVE: \(site.host) baseline=\(site.direct == true) viaPF=\(site.reachable == true)") }
            guard let healthy = await engine.health(targets: sites), healthy.allSatisfy({ $0.reachable == true }) else { throw RoutingError.message("PF health check failed") }
            if CommandLine.arguments.contains("--simulate-ui-exit"), let status = await engine.sessionStatusForTesting() {
                print("WATCHDOG_STATUS: " + status.path)
                fflush(stdout)
                // Deliberately skip cleanup/destructors to simulate the UI dying.
                _exit(0)
            }
            try await engine.stop()
            guard try Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf")) == originalPF,
                  (SCDynamicStoreCopyProxies(nil)! as NSDictionary).isEqual(originalProxies) else { throw RoutingError.message("Unrelated system configuration changed") }
            print("PASS: PF rules, engine liveness, packet counters, real HTTPS, orderly restoration")
            print("PASS: /etc/pf.conf and system proxy configuration unchanged")
        } catch {
            print("PF LIVE FAILED: \(error.localizedDescription)")
            do { try await engine.stop() } catch { print("CLEANUP NEEDS ATTENTION: \(error.localizedDescription)") }
            exit(1)
        }
    }
}
