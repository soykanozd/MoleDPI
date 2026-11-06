// SPDX-License-Identifier: GPL-3.0-only
// Root QUIC guardian. Fixed public UDP/443 policy, immutable installed engines.
// No caller-supplied destinations/rules, default-route edits, DNS or TCP writes.
import Foundation
import Darwin

struct LabFailure: Error { let stage: String }
final class StopFlag: @unchecked Sendable {
    let lock = NSLock(); var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
final class Output: @unchecked Sendable {
    let lock = NSLock(); var data = Data()
    func set(_ data: Data) { lock.lock(); self.data = data; lock.unlock() }
}
func run(_ exe: String, _ args: [String], input: String? = nil) throws -> (Int32, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    let output = Output(), drained = DispatchSemaphore(value: 0), exited = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in exited.signal() }
    var writer: Pipe?
    if input != nil { let stream = Pipe(); writer = stream; p.standardInput = stream }
    else { p.standardInput = FileHandle.nullDevice }
    try p.run()
    DispatchQueue.global().async { output.set(pipe.fileHandleForReading.readDataToEndOfFile()); drained.signal() }
    if let input, let writer { writer.fileHandleForWriting.write(Data(input.utf8)); try writer.fileHandleForWriting.close() }
    if exited.wait(timeout: .now() + 3) == .timedOut {
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        _ = exited.wait(timeout: .now() + 2)
        throw LabFailure(stage: "command-timeout")
    }
    guard drained.wait(timeout: .now() + 1) == .success else { throw LabFailure(stage: "output-timeout") }
    return (p.terminationStatus, String(decoding: output.data, as: UTF8.self))
}
func assignedLocal(_ address: String) -> Bool {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return false }
    defer { freeifaddrs(first) }
    var next: UnsafeMutablePointer<ifaddrs>? = first
    while let item = next {
        defer { next = item.pointee.ifa_next }
        guard let addr = item.pointee.ifa_addr, [UInt8(AF_INET), UInt8(AF_INET6)].contains(addr.pointee.sa_family) else { continue }
        var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &text, socklen_t(text.count), nil, 0, NI_NUMERICHOST) == 0,
           String(cString: text) == address, !address.hasPrefix("127."), address != "::1", !address.hasPrefix("fe80:") { return true }
    }
    return false
}
@main struct UDPService {
    static func main() {
        do {
            if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--recover" { try recover(CommandLine.arguments[2]) }
            else { try execute() }
        }
        catch { print("FAIL physical supervisor: " + ((error as? LabFailure)?.stage ?? "operation")); exit(1) }
    }
    static func recover(_ session: String) throws {
        guard geteuid() == 0, let id = UUID(uuidString:session), id.uuidString == session else { throw LabFailure(stage:"recovery-request") }
        let resources = URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent()
        let journal = URL(fileURLWithPath:"/var/run/moledpi-udp-"+session+"/private/state.journal")
        var st = stat()
        guard lstat(resources.path,&st) == 0, st.st_uid == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_mode & 0o022 == 0 else { throw LabFailure(stage:"recovery-directory") }
        guard lstat(journal.path,&st) == 0 else { return }
        guard st.st_uid == 0, st.st_mode & S_IFMT == S_IFREG, st.st_mode & 0o077 == 0, st.st_size < 4096,
              let values = try JSONSerialization.jsonObject(with:Data(contentsOf:journal)) as? [String:Any],
              values["session"] as? String == session else { throw LabFailure(stage:"recovery-journal") }
        let anchor = "com.apple/MoleDPI-UDP-" + session
        guard try run("/sbin/pfctl",["-a",anchor,"-f","-"],input:"").0 == 0 else { throw LabFailure(stage:"recovery-rule") }
        func executable(_ pid: Int32) -> String? {
            var bytes = [UInt8](repeating:0,count:4096)
            let size = proc_pidpath(pid,&bytes,UInt32(bytes.count))
            guard size > 0 else { return nil }
            return String(decoding:bytes.prefix(Int(size)).prefix(while:{$0 != 0}),as:UTF8.self)
        }
        for (key,name) in [("tunnelPID","tunnel-runner"),("enginePID","ciadpi")] {
            guard let number = values[key] as? NSNumber else { continue }
            let pid = number.int32Value, expected = resources.appendingPathComponent(name).path
            guard pid > 1, executable(pid) == expected else { continue }
            kill(pid,SIGTERM)
            let end = Date().addingTimeInterval(2)
            while executable(pid) == expected && Date() < end { Thread.sleep(forTimeInterval:0.02) }
            if executable(pid) == expected { kill(pid,SIGKILL) }
            let gone = Date().addingTimeInterval(2)
            while executable(pid) == expected && Date() < gone { Thread.sleep(forTimeInterval:0.02) }
            guard executable(pid) != expected else { throw LabFailure(stage:"recovery-process") }
        }
        if let device = values["device"] as? String {
            guard (200...239).map({"utun"+String($0)}).contains(device) else { throw LabFailure(stage:"recovery-interface") }
            let end = Date().addingTimeInterval(1)
            while if_nametoindex(device) != 0 && Date() < end { Thread.sleep(forTimeInterval:0.02) }
            guard if_nametoindex(device) == 0 else { throw LabFailure(stage:"recovery-interface-still-present") }
        }
        if let reference = values["token"] as? String {
            guard !reference.isEmpty, reference.count <= 32, reference.utf8.allSatisfy({$0 >= 48 && $0 <= 57}),
                  try run("/sbin/pfctl",["-X",reference]).0 == 0 else { throw LabFailure(stage:"recovery-reference") }
        }
        let directory = "/var/run/moledpi-udp-" + session
        let status = URL(fileURLWithPath:directory+"/status.json")
        let state:[String:Any] = ["phase":"stopped","session":session,"packets":values["packets"] as? NSNumber ?? 0]
        try JSONSerialization.data(withJSONObject:state).write(to:status,options:.atomic);chmod(status.path,0o644)
        // The user-side driver polls every 50ms. Keep the recovery result visible.
        Thread.sleep(forTimeInterval:1)
        try? FileManager.default.removeItem(atPath:directory)
        try? FileManager.default.removeItem(at:journal)
        print("PASS independent recovery after supervisor crash")
    }
    static func execute() throws {
        let args = CommandLine.arguments
        guard geteuid() == 0, args.count == 9, let uid = UInt32(args[1]), uid >= 500,
              let owner = Int32(args[2]), owner > 1, let client = Int32(args[3]), client > 1,
              args[4] == "internet", let port = UInt16(args[5]), port == 443,
              let uuid = UUID(uuidString: args[6]) else { throw LabFailure(stage: "invalid-request") }
        let ipv6 = args[4].contains(":")
        let gateway = ipv6 ? "fe80::1" : "198.19.255.254"
        let nonce = uuid.uuidString, control = args[7], mode = args[8]
        guard mode == "session" else { throw LabFailure(stage: "invalid-mode") }
        for pid in [owner,client] {
            let info = try run("/bin/ps", ["-o", "uid=", "-p", String(pid)])
            guard info.0 == 0, UInt32(info.1.trimmingCharacters(in: .whitespacesAndNewlines)) == (pid == client ? 0 : uid) else { throw LabFailure(stage: "caller-identity") }
        }
        let resources = URL(fileURLWithPath: args[0]).deletingLastPathComponent()
        var st = stat()
        guard lstat(resources.path, &st) == 0, st.st_uid == 0, st.st_mode & S_IFMT == S_IFDIR,
              st.st_mode & 0o022 == 0, resources.path == "/Library/PrivilegedHelperTools/local.moledpi" else { throw LabFailure(stage: "resource-directory") }
        for name in ["ciadpi", "tunnel-runner"] {
            let url = resources.appendingPathComponent(name)
            guard lstat(url.path, &st) == 0, st.st_uid == 0, st.st_mode & S_IFMT == S_IFREG,
                  st.st_mode & 0o022 == 0 else { throw LabFailure(stage: "resource-ownership") }
        }
        let directory = "/var/run/moledpi-udp-" + nonce
        guard mkdir(directory, 0o755) == 0 else { throw LabFailure(stage: "exclusive-status-directory") }
        guard chmod(directory, 0o755) == 0 else { throw LabFailure(stage:"status-directory-permissions") }
        let privateDir = URL(fileURLWithPath:directory+"/private")
        guard mkdir(privateDir.path,0o700) == 0 else { throw LabFailure(stage:"private-directory") }
        let statusURL = URL(fileURLWithPath: directory + "/status.json")
        let name = "com.apple/MoleDPI-UDP-" + nonce
        let engine = Process(), tunnel = Process()
        var loaded = false, token: String?, packets: UInt64 = 0
        var device: String?
        var result = "starting", problem: String?
        var stoppedCleanly = false
        let flag = StopFlag()
        let signals: [DispatchSourceSignal] = [SIGTERM,SIGINT,SIGHUP].map { number in
            signal(number,SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal:number,queue:.global())
            source.setEventHandler { flag.set() }; source.resume(); return source
        }
        defer { signals.forEach { $0.cancel() } }
        func journal() -> Bool {
            var data:[String:Any] = ["session":nonce,"packets":packets]
            if engine.processIdentifier > 1 { data["enginePID"] = engine.processIdentifier }
            if tunnel.processIdentifier > 1 { data["tunnelPID"] = tunnel.processIdentifier }
            if let device { data["device"] = device }
            if let token { data["token"] = token }
            let file = privateDir.appendingPathComponent("state.journal")
            do { let encoded = try JSONSerialization.data(withJSONObject:data); try encoded.write(to:file,options:.atomic); return chmod(file.path,0o600) == 0 } catch { return false }
        }
        func status(_ phase: String) {
            if !journal() { problem = "recovery-journal-write"; flag.set() }
            var value: [String:Any] = ["phase":phase,"packets":packets,"session":nonce]
            if let problem { value["problem"] = problem }
            if let data = try? JSONSerialization.data(withJSONObject:value) {
                try? data.write(to:statusURL,options:.atomic); chmod(statusURL.path,0o644)
            }
        }
        func readControl() -> String? {
            let fd = open(control,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
            guard fd >= 0 else { return "stop" }; defer { close(fd) }
            var info = stat()
            guard fstat(fd,&info) == 0, info.st_uid == uid, info.st_mode & S_IFMT == S_IFREG,
                  info.st_size > 0, info.st_size < 160 else { return "stop" }
            var buffer = [UInt8](repeating:0,count:160)
            let count = read(fd,&buffer,buffer.count)
            let text = String(decoding:buffer.prefix(max(0,count)),as:UTF8.self)
            return text == nonce && Date().timeIntervalSince1970-Double(info.st_mtimespec.tv_sec)<6 ? "wait" : "stop"
        }
        func stopProcess(_ process: Process) -> Bool {
            guard process.isRunning else { return true }
            process.terminate()
            let end = Date().addingTimeInterval(2)
            while process.isRunning && Date() < end { Thread.sleep(forTimeInterval:0.02) }
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            let final = Date().addingTimeInterval(2)
            while process.isRunning && Date() < final { Thread.sleep(forTimeInterval:0.02) }
            return !process.isRunning
        }
        func cleanup() -> Bool {
            var ok = true
            // Remove routing before releasing the tunnel. No PF states are created.
            if loaded {
                do { let output = try run("/sbin/pfctl",["-a",name,"-f","-"],input:""); ok = output.0 == 0 }
                catch { ok = false }
            }
            if !ok { return false } // Keep the working tunnel for a repair retry.
            if !stopProcess(tunnel) { ok = false }
            if !stopProcess(engine) { ok = false }
            if let reference = token {
                do { let output = try run("/sbin/pfctl",["-X",reference]); if output.0 != 0 { ok = false } else { token = nil } }
                catch { ok = false }
            }
            if let device {
                let gone = Date().addingTimeInterval(1)
                while if_nametoindex(device) != 0 && Date() < gone { Thread.sleep(forTimeInterval:0.02) }
                if if_nametoindex(device) != 0 { ok = false }
            }
            if loaded {
                do { let rules = try run("/sbin/pfctl",["-a",name,"-sr"]); if rules.0 != 0 || rules.1.contains("route-to") { ok = false } }
                catch { ok = false }
            }
            return ok
        }
        status("starting")
        do {
            let global = try run("/sbin/pfctl",["-sr"])
            guard global.0 == 0, global.1.contains("anchor \"com.apple/*\"") else { throw LabFailure(stage:"anchor-unavailable") }
            let selected = (200...239).map { "utun" + String($0) }.first { if_nametoindex($0) == 0 }
            guard let selected else { throw LabFailure(stage:"no-free-interface") }
            if !ipv6 {
            let existingRoute = try run("/sbin/route",["-n","get"] + (ipv6 ? ["-inet6"] : []) + [gateway])
            guard (ipv6 && existingRoute.0 != 0) || (existingRoute.0 == 0 &&
                  existingRoute.1.range(of:#"destination:\s*default"#,options:.regularExpression) != nil) else {
                throw LabFailure(stage:"test-address-route-conflict")
            }
            }
            // IPv6 uses a link-local gateway scoped to the new interface only.
            // Fixed loopback SOCKS port. An occupied port fails closed.
            engine.executableURL = resources.appendingPathComponent("tunnel-runner")
            engine.arguments = [resources.appendingPathComponent("ciadpi").path,"--proxy"]
            engine.standardOutput = FileHandle.nullDevice; engine.standardError = FileHandle.nullDevice; engine.standardInput = FileHandle.nullDevice
            guard !flag.stopped else { throw LabFailure(stage:"cancelled") }
            try engine.run()
            guard journal() else { throw LabFailure(stage:"engine-journal") }
            let ready = Date().addingTimeInterval(3)
            while !ListenerReadiness.ownsTCPListener(pid:engine.processIdentifier,port:19084) {
                guard engine.isRunning, Date() < ready, !flag.stopped else { throw LabFailure(stage:"engine-not-ready") }
                Thread.sleep(forTimeInterval:0.02)
            }
            let config = privateDir.appendingPathComponent("udp.yml")
            let addressLine = ipv6 ? "ipv6: \"\(gateway)\"" : "ipv4: \(gateway)"
            let text = "tunnel:\n  name: \(selected)\n  mtu: 1500\n  \(addressLine)\n  ipv6: fe80::1\nsocks5:\n  address: 127.0.0.1\n  port: 19084\n  udp: udp\nmisc:\n  max-session-count: 32\n  log-level: error\n  udp-read-write-timeout: 2000\n"
            try Data(text.utf8).write(to:config,options:.atomic); chmod(config.path,0o600)
            tunnel.executableURL = resources.appendingPathComponent("tunnel-runner"); tunnel.arguments = [config.path,"--physical"]
            tunnel.standardOutput = FileHandle.nullDevice; tunnel.standardError = FileHandle.nullDevice; tunnel.standardInput = FileHandle.nullDevice
            guard !flag.stopped else { throw LabFailure(stage:"cancelled") }
            try tunnel.run()
            device = selected
            guard journal() else { throw LabFailure(stage:"tunnel-journal") }
            let interfaceReady = Date().addingTimeInterval(3)
            while if_nametoindex(selected) == 0 {
                guard tunnel.isRunning, Date() < interfaceReady, !flag.stopped else { throw LabFailure(stage:"tunnel-not-ready") }
                Thread.sleep(forTimeInterval:0.02)
            }
            device = selected
            let rules = """
            table <udp_local4> const { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 198.18.0.0/15, 224.0.0.0/4, 240.0.0.0/4 }
            table <udp_local6> const { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8 }
            pass out quick route-to (\(selected) \(gateway)) inet proto udp from any to !<udp_local4> port 443 user \(uid) no state
            pass out quick route-to (\(selected) fe80::1) inet6 proto udp from any to !<udp_local6> port 443 user \(uid) no state
            
            """
            guard try run("/sbin/pfctl",["-n","-a",name,"-f","-"],input:rules).0 == 0 else { throw LabFailure(stage:"rule-syntax") }
            let enabled = try run("/sbin/pfctl",["-E"])
            guard enabled.0 == 0, let match = enabled.1.range(of:#"Token\s*:\s*([0-9]+)"#,options:.regularExpression) else { throw LabFailure(stage:"pf-reference") }
            token = String(enabled.1[match]).split(separator:":").last!.trimmingCharacters(in:.whitespacesAndNewlines)
            guard let token, token.count <= 32, !token.isEmpty, token.allSatisfy({ $0.isNumber }) else { throw LabFailure(stage:"invalid-reference") }
            loaded = true
            guard journal() else { throw LabFailure(stage:"rule-journal") }
            guard !flag.stopped else { throw LabFailure(stage:"cancelled") }
            guard try run("/sbin/pfctl",["-a",name,"-f","-"],input:rules).0 == 0 else { throw LabFailure(stage:"apply-rule") }
            status("active")
            let end = Date.distantFuture
            
            while Date() < end, !flag.stopped, kill(owner,0) == 0, kill(client,0) == 0, engine.isRunning, tunnel.isRunning {
                let command = readControl()
                if command == "stop" { result = "normal"; break }
                let current = try run("/sbin/pfctl",["-a",name,"-vvsr"])
                let regex = try NSRegularExpression(pattern:#"Packets:\s*([0-9]+)"#)
                packets = regex.matches(in:current.1,range:NSRange(current.1.startIndex...,in:current.1)).reduce(0) { count,match in
                    guard let range = Range(match.range(at:1),in:current.1), let number = UInt64(current.1[range]) else { return count }
                    return count + number
                }
                status("active"); Thread.sleep(forTimeInterval:0.5)
            }
            if result == "starting" { result = "normal" }
            if loaded {
                let final = try run("/sbin/pfctl",["-a",name,"-vvsr"])
                let regex = try NSRegularExpression(pattern:#"Packets:\s*([0-9]+)"#)
                packets = regex.matches(in:final.1,range:NSRange(final.1.startIndex...,in:final.1)).reduce(0) { count, match in
                    guard let range = Range(match.range(at:1),in:final.1), let number = UInt64(final.1[range]) else { return count }
                    return count + number
                }
            }
            guard result == "normal" else { throw LabFailure(stage:"scenario-or-counter") }
        } catch { problem = (error as? LabFailure)?.stage ?? "operation" }
        for _ in 0..<3 {
            if cleanup() { stoppedCleanly = true; break }
            Thread.sleep(forTimeInterval:0.2)
        }
        if !stoppedCleanly { problem = "cleanup-failed" }
        status(problem == nil ? "stopped" : "failed")
        // Allow the unprivileged driver to observe final state before stage cleanup.
        let ack = Date().addingTimeInterval(3)
        while false && Date() < ack { Thread.sleep(forTimeInterval:0.05) }
        if stoppedCleanly {
            try? FileManager.default.removeItem(atPath:directory)
            try? FileManager.default.removeItem(at:privateDir.appendingPathComponent("state.journal"))
        }
        guard stoppedCleanly, problem == nil else { throw LabFailure(stage:problem ?? "cleanup") }
        print("PASS physical UDP routing and cleanup: " + mode)
    }
}
