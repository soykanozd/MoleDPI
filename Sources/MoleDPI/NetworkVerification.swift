// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import SystemConfiguration
import Darwin

// Opt-in integration check executed by the actual installed, authenticated client.
// No caller-controlled destinations, PF rules, worker arguments or executable paths.
enum NetworkVerification {
    // Opt-in fixed-policy session for external HTTP/3 acceptance tests. The caller
    // can only request a normal connection and stop it; no rules/paths are supplied.
    @MainActor static func quicSession() async -> Int32 {
        let engine = PFConnection()
        let model = Model(engine:engine, monitorNetwork:false)
        let originalFlags = fcntl(STDIN_FILENO, F_GETFL)
        guard originalFlags >= 0, fcntl(STDIN_FILENO,F_SETFL,originalFlags | O_NONBLOCK) == 0 else { return 1 }
        defer { _ = fcntl(STDIN_FILENO,F_SETFL,originalFlags) }
        do {
            let config = try Data(contentsOf:URL(fileURLWithPath:"/etc/pf.conf"))
            let proxy = SCDynamicStoreCopyProxies(nil) as NSDictionary?
            model.connect(); await model.task?.value
            guard model.state == .on, model.quicActive == true else { throw RoutingError.message("QUIC session is unavailable.") }
            print("QUIC_SESSION_READY"); fflush(stdout)
            let deadline = Date().addingTimeInterval(900)
            var byte:UInt8 = 0
            while Date() < deadline {
                let received = read(STDIN_FILENO,&byte,1)
                if received == 0 || received > 0 { break }
                guard errno == EAGAIN || errno == EWOULDBLOCK else { throw RoutingError.message("Verification input failed.") }
                guard model.state == .on else { throw RoutingError.message("The verification session stopped.") }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            model.disconnect(); await model.task?.value
            let settle = Date().addingTimeInterval(3)
            while (SCDynamicStoreCopyProxies(nil) as NSDictionary?) != proxy && Date() < settle {
                try await Task.sleep(nanoseconds:50_000_000)
            }
            guard model.state == .off, !model.recoveryNeeded,
                  try Data(contentsOf:URL(fileURLWithPath:"/etc/pf.conf")) == config,
                  (SCDynamicStoreCopyProxies(nil) as NSDictionary?) == proxy else { throw RoutingError.message("Verification restoration failed.") }
            print("PASS QUIC session stopped and network restored"); fflush(stdout)
            return 0
        } catch {
            model.beginShutdown()
            do { try await model.waitForShutdown() }
            catch { print("FAILED verification cleanup requires attention") }
            print("FAILED QUIC verification: " + FriendlyError.message(error))
            return 1
        }
    }
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
    static func quicHandshake() async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label:"MoleDPI.QUIC.verification")
            let options = NWProtocolQUIC.Options(alpn:["h3"])
            sec_protocol_options_set_tls_server_name(options.securityProtocolOptions,"cloudflare-dns.com")
            let connection = NWConnection(host:"1.1.1.1",port:443,using:NWParameters(quic:options))
            var finished = false
            func finish(_ success: Bool) {
                guard !finished else { return }; finished = true
                connection.stateUpdateHandler = nil; connection.cancel()
                continuation.resume(returning:success)
            }
            connection.stateUpdateHandler = { state in
                if case .ready = state { finish(true) }
                if case .failed = state { finish(false) }
            }
            connection.start(queue:queue)
            queue.asyncAfter(deadline:.now()+8) { finish(false) }
        }
    }
    @MainActor static func run(encryptedDNS: Bool = false, fallback: Bool = false, endurance: Bool = false) async -> Int32 {
        let engine = PFConnection(requireDNSRecovery: encryptedDNS)
        let targets = ["example.com", "discord.com", "www.roblox.com"].map { SiteCheck(host: $0, name: $0) }
        do {
            let config = try Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf"))
            let proxy = SCDynamicStoreCopyProxies(nil) as NSDictionary?
            _ = try await ServiceClient.prepare()
            let model = Model(engine: engine, sites: targets)
            for cycle in 1...(endurance ? 100 : ((encryptedDNS || fallback) ? 2 : 10)) {
                let started = DispatchTime.now().uptimeNanoseconds
                model.connect()
                await model.task?.value
                guard model.state == .on else { throw RoutingError.message(model.detail) }
                print(String(format:"MEASURE connect_ms %.2f",Double(DispatchTime.now().uptimeNanoseconds-started)/1_000_000)); fflush(stdout)
                let sites = model.sites
                let status = await engine.sessionStatusForTesting()
                if engine.requestsQUIC, let status,
                   let active = try JSONSerialization.jsonObject(with:Data(contentsOf:status)) as? [String:Any] {
                    guard active["udpActive"] as? Bool == !fallback else { throw RoutingError.message("UDP helper was not active.") }
                    if cycle == 1 && !fallback {
                        let handshake = await quicHandshake()
                        print(handshake ? "PASS: real public QUIC handshake with system certificate verification" : "OBSERVATION: public QUIC handshake failed; ISP bypass is unverified")
                        fflush(stdout)
                        if handshake {
                            let udpFile = URL(fileURLWithPath:"/var/run/moledpi-udp-"+status.deletingLastPathComponent().lastPathComponent+"/status.json")
                            let end = Date().addingTimeInterval(2)
                            var count = 0
                            repeat {
                                if let bytes = try? Data(contentsOf:udpFile), let info = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] { count = (info["packets"] as? NSNumber)?.intValue ?? 0 }
                                if count == 0 { try await Task.sleep(nanoseconds:50_000_000) }
                            } while count == 0 && Date() < end
                            guard count > 0 else { throw RoutingError.message("No UDP PF packets counted during QUIC handshake.") }
                            print("PASS: QUIC handshake crossed the owned UDP PF anchor")
                        }
                    }
                }
                if fallback { guard model.quicActive == false else { throw RoutingError.message("Fallback state was not shown.") }; print("PASS: TCP stayed verified while QUIC was unavailable") }
                model.disconnect()
                await model.task?.value
                guard model.state == .off && !model.recoveryNeeded else { throw RoutingError.message(model.detail) }
                let settle = Date().addingTimeInterval(3)
                while (SCDynamicStoreCopyProxies(nil) as NSDictionary?) != proxy && Date() < settle {
                    try await Task.sleep(nanoseconds:50_000_000)
                }
                guard sites.allSatisfy({ $0.reachable == true }), let status,
                      let journal = try JSONSerialization.jsonObject(with: Data(contentsOf: status)) as? [String: Any],
                      journal["phase"] as? String == "stopped", journal["pfToken"] == nil,
                      try Data(contentsOf: URL(fileURLWithPath: "/etc/pf.conf")) == config,
                      (SCDynamicStoreCopyProxies(nil) as NSDictionary?) == proxy else {
                    print("CHECK sites="+String(sites.allSatisfy({$0.reachable == true}))+" pf="+String((try? Data(contentsOf:URL(fileURLWithPath:"/etc/pf.conf"))) == config)+" proxy="+String((SCDynamicStoreCopyProxies(nil) as NSDictionary?) == proxy))
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
