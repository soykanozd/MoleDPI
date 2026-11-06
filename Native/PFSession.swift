// SPDX-License-Identifier: GPL-3.0-only
// Privileged, fixed-purpose session. No shell execution, arbitrary executable,
// host-list download, packet logging, sudoers rule or launch-at-login service.
import Foundation
import Darwin
import SystemConfiguration

struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct Result { let code: Int32; let text: String }
func command(_ executable: String, _ args: [String], input: String? = nil) throws -> Result {
    let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
    let output = Pipe(); p.standardOutput = output; p.standardError = output
    let finished = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in finished.signal() }
    var writer: Pipe?
    if let input { let pipe = Pipe(); writer = pipe; p.standardInput = pipe; try p.run(); pipe.fileHandleForWriting.write(Data(input.utf8)); try pipe.fileHandleForWriting.close() }
    else { p.standardInput = FileHandle.nullDevice; try p.run() }
    _ = writer
    // Outputs here are small PF configuration/status messages, never packet data.
    let data = output.fileHandleForReading.readDataToEndOfFile(); finished.wait()
    return Result(code: p.terminationStatus, text: String(decoding: data, as: UTF8.self))
}
let privilegedDirectory = "/Library/PrivilegedHelperTools/local.moledpi"
let pfctl = "/sbin/pfctl"
func anchor(_ uid: UInt32) -> String { "com.apple/MoleDPI-\(uid)" }
func rules(_ uid: UInt32) -> String {
    // Exclude DESTINATION private/local networks (not the LAN source address).
    // Only this login user's TCP 80/443 is redirected. Root engine is excluded.
    """
    table <moledpi_local4> const { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
    table <moledpi_local6> const { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8 }
    rdr pass on lo0 inet proto tcp from !127.0.0.0/8 to !<moledpi_local4> port { 80, 443 } -> 127.0.0.1 port 18082
    rdr pass on lo0 inet6 proto tcp from !::1 to !<moledpi_local6> port { 80, 443 } -> fe80::1 port 18082
    pass out quick route-to (lo0 127.0.0.1) inet proto tcp from any to !<moledpi_local4> port { 80, 443 } user \(uid) keep state
    pass out quick route-to (lo0 fe80::1) inet6 proto tcp from any to !<moledpi_local6> port { 80, 443 } user \(uid) keep state
    """ + "\n"
}
func secureRootDirectory(_ path: String) throws {
    var st = stat()
    if lstat(path, &st) != 0 {
        guard mkdir(path, 0o755) == 0 else { throw Failure(message: "Could not create a secure working directory.") }
        guard lstat(path, &st) == 0 else { throw Failure(message: "Could not inspect the working directory.") }
    }
    guard st.st_uid == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_mode & 0o022 == 0 else { throw Failure(message: "Untrusted privileged directory rejected.") }
}
final class SignalFlag: @unchecked Sendable {
    let lock = NSLock(); private var value = false
    func stop() { lock.lock(); value = true; lock.unlock() }
    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
@main struct Session {
    static func main() {
        do { try run() } catch { fputs("MoleDPI: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--print-rules", let uid = UInt32(CommandLine.arguments[2]), uid >= 500 {
            print(rules(uid)); return
        }
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--repair",
           geteuid() == 0, let uid = UInt32(CommandLine.arguments[2]), uid >= 500,
           let uuid = UUID(uuidString: CommandLine.arguments[3]) {
            let dir = "/var/run/moledpi/\(uuid.uuidString)"
            try secureRootDirectory("/var/run/moledpi"); try secureRootDirectory(dir)
            let url = URL(fileURLWithPath: dir + "/status.json")
            var st = stat()
            guard lstat(url.path, &st) == 0, st.st_uid == 0, st.st_mode & S_IFMT == S_IFREG, st.st_mode & 0o022 == 0, st.st_size < 32768,
                  let journal = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  (journal["uid"] as? NSNumber)?.uint32Value == uid else { throw Failure(message: "Trusted PF recovery record not found.") }
            guard try command(privilegedDirectory+"/moledpi-udp",["--recover",uuid.uuidString]).code == 0 else { throw Failure(message:"UDP cleanup could not be verified.") }
            if let pid = (journal["enginePID"] as? NSNumber)?.int32Value, pid > 1 {
                var buffer = [UInt8](repeating:0,count:4096)
                let size = proc_pidpath(pid,&buffer,UInt32(buffer.count))
                if size > 0 && String(decoding:buffer.prefix(Int(size)).prefix(while:{$0 != 0}),as:UTF8.self) == privilegedDirectory+"/tpws" { kill(pid,SIGTERM) }
            }
            let emptied = try command(pfctl, ["-a", anchor(uid), "-f", "-"], input: "")
            guard emptied.code == 0 else { throw Failure(message: "Could not clear MoleDPI PF rules.") }
            if let token = journal["pfToken"] as? String {
                guard !token.isEmpty, token.count <= 32, token.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Failure(message: "Invalid PF reference.") }
                let released = try command(pfctl, ["-X", token])
                guard released.code == 0 else { throw Failure(message: "Could not release the MoleDPI PF reference.") }
            }
            let done: [String: Any] = ["phase": "stopped", "message": "", "uid": uid, "checkedAt": Date().timeIntervalSince1970]
            try JSONSerialization.data(withJSONObject: done).write(to: url, options: .atomic)
            chmod(url.path, 0o644)
            return
        }
        guard geteuid() == 0, CommandLine.arguments.count == 7,
              let uid = UInt32(CommandLine.arguments[1]), uid >= 500,
              let parent = Int32(CommandLine.arguments[2]), parent > 1,
              let uuid = UUID(uuidString: CommandLine.arguments[3]),
              let profile = Int(CommandLine.arguments[5]), (0...11).contains(profile) else { throw Failure(message: "Invalid session request.") }
        let heartbeat = CommandLine.arguments[4]
        // Last argument is a version marker, not executable/configuration input.
        guard CommandLine.arguments[6] == "v1" else { throw Failure(message: "Session protocol version mismatch.") }
        let tokenString = uuid.uuidString
        let owner = try command("/bin/ps", ["-o", "uid=", "-p", String(parent)])
        guard owner.code == 0, UInt32(owner.text.trimmingCharacters(in: .whitespacesAndNewlines)) == uid else { throw Failure(message: "Could not verify the request owner.") }
        func alive() -> Bool {
            var st = stat()
            guard kill(parent, 0) == 0 else { return false }
            let fd = open(heartbeat, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { return false }
            defer { close(fd) }
            guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG,
                  st.st_uid == uid, st.st_size < 100,
                  Date().timeIntervalSince1970 - Double(st.st_mtimespec.tv_sec) < 6 else { return false }
            var bytes = [UInt8](repeating: 0, count: 100)
            let n = read(fd, &bytes, bytes.count)
            return n > 0 && String(decoding: bytes.prefix(n), as: UTF8.self) == tokenString
        }
        try secureRootDirectory("/var/run/moledpi")
        let dir = "/var/run/moledpi/\(tokenString)"
        guard mkdir(dir, 0o755) == 0 else { throw Failure(message: "Oturum zaten mevcut.") }
        let stateURL = URL(fileURLWithPath: dir + "/status.json")
        let engine = Process()
        let udp = Process()
        var udpReady = false
        var packetCount: UInt64 = 0
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var stages: [String: Int] = [:]
        func mark(_ label: String) { stages[label] = Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000) }
        func status(_ phase: String, _ message: String = "", token: String? = nil) {
            var value: [String: Any] = ["phase": phase, "message": message, "uid": uid, "pid": getpid()]
            for (label, elapsed) in stages { value[label] = elapsed }
            if let token { value["pfToken"] = token }
            value["udpActive"] = udpReady
            if engine.processIdentifier > 1 { value["enginePID"] = engine.processIdentifier }
            value["packets"] = packetCount
            value["checkedAt"] = Date().timeIntervalSince1970
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) { try? data.write(to: stateURL, options: .atomic); chmod(stateURL.path, 0o644) }
        }
        status("starting")
        guard alive() else {
            status("failed", "Session was cancelled before network configuration.")
            throw Failure(message: "Cancelled session.")
        }
        var pfToken: String?
        var loaded = false
        let name = anchor(uid)
        let signals = SignalFlag()
        let sources: [DispatchSourceSignal] = [SIGTERM, SIGINT, SIGHUP].map { sig in
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { signals.stop() }; source.resume(); return source
        }
        defer { sources.forEach { $0.cancel() } }
        var dnsStore: SCDynamicStore?
        let dnsKey = "State:/Network/Service/MoleDPI-" + tokenString + "/DNS"
        func clean() -> Bool {
            var ok = true
            if let store = dnsStore {
                if !SCDynamicStoreRemoveValue(store, dnsKey as CFString) && SCError() != kSCStatusNoKey { ok = false }
                dnsStore = nil
            }
            if loaded {
                do {
                    let result = try command(pfctl, ["-a", name, "-f", "-"], input: "")
                    ok = result.code == 0
                } catch { ok = false }
            }
            if udp.isRunning {
                udp.terminate()
                let deadline = Date().addingTimeInterval(4)
                while udp.isRunning && Date() < deadline { Thread.sleep(forTimeInterval:0.05) }
                if udp.isRunning { kill(udp.processIdentifier,SIGKILL); udp.waitUntilExit() }
            }
            if profile >= 6 {
                do { if try command(privilegedDirectory+"/moledpi-udp",["--recover",tokenString]).code != 0 { ok = false } }
                catch { ok = false }
            }
            udpReady = false
            if engine.isRunning {
                engine.terminate()
                let deadline = Date().addingTimeInterval(2)
                while engine.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                if engine.isRunning { kill(engine.processIdentifier, SIGKILL) }
                engine.waitUntilExit()
            }
            if let token = pfToken {
                do { let result = try command(pfctl, ["-X", token]); if result.code == 0 { pfToken = nil } else { ok = false } } catch { ok = false }
            }
            return ok
        }
        do {
            // Never flush/reload the global ruleset or rewrite /etc/pf.conf.
            let filter = try command(pfctl, ["-sr"])
            let nat = try command(pfctl, ["-sn"])
            guard filter.code == 0, nat.code == 0,
                  filter.text.contains("anchor \"com.apple/*\""), nat.text.contains("rdr-anchor \"com.apple/*\"") else {
                throw Failure(message: "Required PF anchors are unavailable.")
            }
            let existing = try command(pfctl, ["-a", name, "-sr"])
            let existingNAT = try command(pfctl, ["-a", name, "-sn"])
            guard !existing.text.contains("route-to"), !existingNAT.text.contains("rdr pass") else { throw Failure(message: "Another MoleDPI PF session exists.") }
            let syntax = try command(pfctl, ["-n", "-a", name, "-f", "-"], input: rules(uid))
            guard syntax.code == 0 else { throw Failure(message: "PF rules failed validation: \(syntax.text)") }
            let profiles = [["--split-pos=host+1", "--tlsrec=host+1"], ["--split-pos=2", "--oob=tls"], ["--split-pos=host+1", "--tlsrec=host+1"]]
            engine.executableURL = URL(fileURLWithPath: privilegedDirectory + "/tpws")
            engine.arguments = ["--user=root", "--bind-addr=127.0.0.1", "--bind-iface6=lo0", "--bind-linklocal=force", "--port=18082", "--maxconn=128", "--filter-tcp=80,443", "--filter-l7=http,tls"] + profiles[profile % 3]
            engine.environment = ["PATH": "/usr/bin:/bin", "MOLEDPI_SPLIT_DELAY_US": profile % 3 == 2 ? "20000" : "0"]
            engine.standardOutput = FileHandle.nullDevice; engine.standardError = FileHandle.nullDevice; engine.standardInput = FileHandle.nullDevice
            try engine.run()
            mark("launch")
            let portDeadline = DispatchTime.now() + .seconds(2)
            while !ListenerReadiness.ownsTCPListener(pid: engine.processIdentifier, port: 18082) {
                guard engine.isRunning, !signals.stopped, alive(), DispatchTime.now() < portDeadline else {
                    throw Failure(message: "The network worker did not open its TCP port.")
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard engine.isRunning, alive(), !signals.stopped else { throw Failure(message: "The network session was cancelled.") }
            mark("listen")
            let enabled = try command(pfctl, ["-E"])
            guard enabled.code == 0, let range = enabled.text.range(of: #"Token\s*:\s*([0-9]+)"#, options: .regularExpression) else { throw Failure(message: "Could not acquire a PF activation reference.") }
            pfToken = String(enabled.text[range]).split(separator: ":").last!.trimmingCharacters(in: .whitespacesAndNewlines)
            status("starting", token: pfToken)
            // Mark before loading: a failed pfctl call might have partially applied.
            loaded = true
            let applied = try command(pfctl, ["-a", name, "-f", "-"], input: rules(uid))
            guard applied.code == 0 else { throw Failure(message: "Could not apply PF session rules.") }
            let check = try command(pfctl, ["-a", name, "-sr"])
            guard check.code == 0, check.text.contains("route-to"), engine.isRunning else { throw Failure(message: "Could not verify PF and tpws state.") }
            if profile % 6 >= 3 {
                guard ListenerReadiness.ownsTCPListener(pid: parent, port: 18083) else {
                    throw Failure(message: "Encrypted DNS listener is not owned by the client.")
                }
                let settings: [String: Any] = ["ServerAddresses": ["127.0.0.1"], "ServerPort": 18083,
                    "SupplementalMatchDomains": ["discord.com", "discord.gg", "discordapp.com", "discordapp.net", "roblox.com", "rbxcdn.com"],
                    "SupplementalMatchDomainsNoSearch": 1]
                guard let store = SCDynamicStoreCreate(nil, "MoleDPI DNS" as CFString, nil, nil),
                      SCDynamicStoreAddTemporaryValue(store, dnsKey as CFString, settings as CFDictionary) else {
                    throw Failure(message: "Could not activate scoped DNS recovery.")
                }
                dnsStore = store
            }
            if profile >= 6 {
                udp.executableURL = URL(fileURLWithPath:privilegedDirectory+"/moledpi-udp")
                udp.arguments = [String(uid),String(parent),String(getpid()),"internet","443",tokenString,heartbeat,"session"]
                udp.standardInput = FileHandle.nullDevice; udp.standardOutput = FileHandle.nullDevice; udp.standardError = FileHandle.nullDevice
                try udp.run()
                let deadline = Date().addingTimeInterval(6)
                let file = URL(fileURLWithPath:"/var/run/moledpi-udp-"+tokenString+"/status.json")
                while udp.isRunning && Date() < deadline && alive() && !signals.stopped {
                    if let data = try? Data(contentsOf:file), let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any], object["phase"] as? String == "active" { udpReady = true; break }
                    Thread.sleep(forTimeInterval:0.03)
                }
                guard udpReady else { throw Failure(message:"Experimental UDP engine failed to start. Restoring network settings.") }
            }
            mark("apply")
            status("active", token: pfToken)
            let startupWindow = DispatchTime.now() + .seconds(4)
            var iteration = 0
            while alive() && !signals.stopped && engine.isRunning && (profile < 6 || udp.isRunning) {
                let needsInitialCount = packetCount == 0 && DispatchTime.now() < startupWindow
                if iteration % 4 == 0 || needsInitialCount {
                    let info = try command(pfctl, ["-s", "info"])
                    let own = try command(pfctl, ["-a", name, "-vvsr"])
                    guard info.code == 0, info.text.contains("Status: Enabled"), own.code == 0, own.text.contains("route-to") else {
                        throw Failure(message: "PF rules are no longer active.")
                    }
                    let regex = try NSRegularExpression(pattern: #"Packets:\s*([0-9]+)"#)
                    packetCount = regex.matches(in: own.text, range: NSRange(own.text.startIndex..., in: own.text)).reduce(0) { total, match in
                        guard let range = Range(match.range(at: 1), in: own.text), let number = UInt64(own.text[range]) else { return total }
                        return total + number
                    }
                    status("active", token: pfToken)
                }
                iteration += 1; Thread.sleep(forTimeInterval: needsInitialCount ? 0.12 : 0.5)
            }
            let engineFailed = alive() && !signals.stopped && (!engine.isRunning || (profile >= 6 && !udp.isRunning))
            if clean() { status(engineFailed ? "failed" : "stopped", engineFailed ? "The network engine stopped unexpectedly." : "") }
            else { status("cleanup_failed", "PF cleanup failed. Recovery is required.", token: pfToken) }
        } catch {
            let ok = clean()
            status(ok ? "failed" : "cleanup_failed", error.localizedDescription, token: ok ? nil : pfToken)
            throw error
        }
    }
}
