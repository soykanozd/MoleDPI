// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SystemConfiguration

// Opt-in integration check executed by the actual installed, authenticated client.
// No caller-controlled destinations, PF rules, worker arguments or executable paths.
enum NetworkVerification {
    @MainActor static func run(encryptedDNS: Bool = false) async -> Int32 {
        let engine = PFConnection(requireDNSRecovery: encryptedDNS)
        let targets = ["example.com", "discord.com", "www.roblox.com"].map { SiteCheck(host: $0, name: $0) }
        do {
            let config = try Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf"))
            let proxy = SCDynamicStoreCopyProxies(nil) as NSDictionary?
            _ = try await ServiceClient.prepare()
            let model = Model(engine: engine, sites: targets)
            for cycle in 1...(encryptedDNS ? 2 : 10) {
                model.connect()
                await model.task?.value
                guard model.state == .on else { throw RoutingError.message(model.detail) }
                let sites = model.sites
                let status = await engine.sessionStatusForTesting()
                model.disconnect()
                await model.task?.value
                guard model.state == .off && !model.recoveryNeeded else { throw RoutingError.message(model.detail) }
                guard sites.allSatisfy({ $0.reachable == true }), let status,
                      let journal = try JSONSerialization.jsonObject(with: Data(contentsOf: status)) as? [String: Any],
                      journal["phase"] as? String == "stopped", journal["pfToken"] == nil,
                      try Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf")) == config,
                      (SCDynamicStoreCopyProxies(nil) as NSDictionary?) == proxy else {
                    throw RoutingError.message("Verification failed at cycle " + String(cycle))
                }
                print("PASS: verified HTTPS and restored network, cycle " + String(cycle)); fflush(stdout)
            }
            return 0
        } catch {
            print("FAILED: " + error.localizedDescription)
            do { try await engine.stop() } catch { print("Recovery required: " + error.localizedDescription) }
            return 1
        }
    }
}
