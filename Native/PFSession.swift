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
        guard mkdir(path, 0o755) == 0 else { throw Failure(message: "Güvenli çalışma dizini oluşturulamadı.") }
        guard lstat(path, &st) == 0 else { throw Failure(message: "Çalışma dizini okunamadı.") }
    }
    guard st.st_uid == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_mode & 0o022 == 0 else { throw Failure(message: "Güvenilmeyen ayrıcalıklı dizin reddedildi.") }
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
                  (journal["uid"] as? NSNumber)?.uint32Value == uid else { throw Failure(message: "Güvenilir PF kurtarma kaydı bulunamadı.") }
            let emptied = try command(pfctl, ["-a", anchor(uid), "-f", "-"], input: "")
            guard emptied.code == 0 else { throw Failure(message: "MoleDPI PF kuralları temizlenemedi.") }
            if let token = journal["pfToken"] as? String {
                guard !token.isEmpty, token.count <= 32, token.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Failure(message: "Geçersiz PF referansı.") }
                let released = try command(pfctl, ["-X", token])
                guard released.code == 0 else { throw Failure(message: "MoleDPI PF referansı bırakılamadı; kılavuzdan denetle.") }
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
              let profile = Int(CommandLine.arguments[5]), (0...5).contains(profile) else { throw Failure(message: "Geçersiz oturum isteği.") }
        let heartbeat = CommandLine.arguments[4]
        // Last argument is a version marker, not executable/configuration input.
        guard CommandLine.arguments[6] == "v1" else { throw Failure(message: "Oturum sürümü uyuşmuyor.") }
        let tokenString = uuid.uuidString
        let owner = try command("/bin/ps", ["-o", "uid=", "-p", String(parent)])
        guard owner.code == 0, UInt32(owner.text.trimmingCharacters(in: .whitespacesAndNewlines)) == uid else { throw Failure(message: "İstek sahibi doğrulanamadı.") }
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
        var packetCount: UInt64 = 0
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var stages: [String: Int] = [:]
        func mark(_ label: String) { stages[label] = Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000) }
        func status(_ phase: String, _ message: String = "", token: String? = nil) {
            var value: [String: Any] = ["phase": phase, "message": message, "uid": uid, "pid": getpid()]
            for (label, elapsed) in stages { value[label] = elapsed }
            if let token { value["pfToken"] = token }
            value["packets"] = packetCount
            value["checkedAt"] = Date().timeIntervalSince1970
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) { try? data.write(to: stateURL, options: .atomic); chmod(stateURL.path, 0o644) }
        }
        status("starting")
        guard alive() else {
            status("failed", "Session was cancelled before network configuration.")
            throw Failure(message: "Cancelled session.")
        }
        let engine = Process()
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
                throw Failure(message: "PF ana bağlantı noktaları etkin değil. Genel güvenlik duvarı kuralları değiştirilmedi.")
            }
            let existing = try command(pfctl, ["-a", name, "-sr"])
            let existingNAT = try command(pfctl, ["-a", name, "-sn"])
            guard !existing.text.contains("route-to"), !existingNAT.text.contains("rdr pass") else { throw Failure(message: "Başka bir MoleDPI PF oturumu var.") }
            let syntax = try command(pfctl, ["-n", "-a", name, "-f", "-"], input: rules(uid))
            guard syntax.code == 0 else { throw Failure(message: "PF kuralları bu macOS sürümünde doğrulanamadı: \(syntax.text)") }
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
            guard enabled.code == 0, let range = enabled.text.range(of: #"Token\s*:\s*([0-9]+)"#, options: .regularExpression) else { throw Failure(message: "PF etkinleştirme referansı alınamadı.") }
            pfToken = String(enabled.text[range]).split(separator: ":").last!.trimmingCharacters(in: .whitespacesAndNewlines)
            status("starting", token: pfToken)
            // Mark before loading: a failed pfctl call might have partially applied.
            loaded = true
            let applied = try command(pfctl, ["-a", name, "-f", "-"], input: rules(uid))
            guard applied.code == 0 else { throw Failure(message: "PF oturum kuralları uygulanamadı.") }
            let check = try command(pfctl, ["-a", name, "-sr"])
            guard check.code == 0, check.text.contains("route-to"), engine.isRunning else { throw Failure(message: "PF / tpws durumu doğrulanamadı.") }
            if profile >= 3 {
                let settings: [String: Any] = ["ServerAddresses": ["9.9.9.9"], "ServerPort": 9953,
                    "SupplementalMatchDomains": ["discord.com", "discord.gg", "discordapp.com", "discordapp.net", "roblox.com", "rbxcdn.com"],
                    "SupplementalMatchDomainsNoSearch": 1]
                guard let store = SCDynamicStoreCreate(nil, "MoleDPI DNS" as CFString, nil, nil),
                      SCDynamicStoreAddTemporaryValue(store, dnsKey as CFString, settings as CFDictionary) else {
                    throw Failure(message: "Could not activate scoped DNS recovery.")
                }
                dnsStore = store
            }
            mark("apply")
            status("active", token: pfToken)
            let startupWindow = DispatchTime.now() + .seconds(4)
            var iteration = 0
            while alive() && !signals.stopped && engine.isRunning {
                let needsInitialCount = packetCount == 0 && DispatchTime.now() < startupWindow
                if iteration % 4 == 0 || needsInitialCount {
                    let info = try command(pfctl, ["-s", "info"])
                    let own = try command(pfctl, ["-a", name, "-vvsr"])
                    guard info.code == 0, info.text.contains("Status: Enabled"), own.code == 0, own.text.contains("route-to") else {
                        throw Failure(message: "PF kuralları artık etkin değil.")
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
            let engineFailed = !engine.isRunning
            if clean() { status(engineFailed ? "failed" : "stopped", engineFailed ? "tpws beklenmedik biçimde kapandı." : "") }
            else { status("cleanup_failed", "PF temizlenemedi. Ağ onarımı gerekli.", token: pfToken) }
        } catch {
            let ok = clean()
            status(ok ? "failed" : "cleanup_failed", error.localizedDescription, token: ok ? nil : pfToken)
            throw error
        }
    }
}
