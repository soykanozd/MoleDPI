// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SystemConfiguration

// Opt-in integration check executed by the actual installed, authenticated client.
// No caller-controlled destinations, PF rules, worker arguments or executable paths.
enum NetworkVerification {
    // Real engine and HTTPS, with controller events injected. This does not
    // physically switch Wi-Fi or put the computer to sleep.
    @MainActor static func recovery() async -> Int32 {
        let engine = PFConnection()
        let model = Model(engine: engine, monitorNetwork: false)
        let config = try? Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf"))
        let proxy = SCDynamicStoreCopyProxies(nil) as NSDictionary?
        do {
            model.connect(); await model.task?.value
            guard model.state == .on else { throw RoutingError.message(model.detail) }
            let original = await engine.sessionStatusForTesting()
            for cycle in 1...3 {
                model.networkChanged(false)
                model.networkChanged(true)
                model.systemWillSleep()
                model.systemDidWake()
                let deadline = Date().addingTimeInterval(35)
                while model.recovering && Date() < deadline {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                guard !model.recovering, model.state == .on,
                      await engine.sessionStatusForTesting() == original,
                      model.sites.contains(where: { $0.reachable == true }) else {
                    throw RoutingError.message("Network event recovery check failed.")
                }
                print("PASS real HTTPS after injected path/wake events, unchanged engine session, cycle \(cycle)"); fflush(stdout)
            }
            model.disconnect(); await model.task?.value
            guard model.state == .off, !model.recoveryNeeded,
                  try Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf")) == config,
                  (SCDynamicStoreCopyProxies(nil) as NSDictionary?) == proxy else {
                throw RoutingError.message("Network restoration failed.")
            }
            print("PASS restored PF configuration and proxy settings")
            return 0
        } catch {
            model.beginShutdown()
            do { try await model.waitForShutdown() }
            catch { print("FAILED cleanup requires attention") }
            print("FAILED recovery verification: " + FriendlyError.message(error))
            return 1
        }
    }
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
