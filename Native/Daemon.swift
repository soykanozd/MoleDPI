// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

// launchd starts this root service on demand. One worker at a time across clients.
private let workerLock = NSLock()
private var worker: Process?
// Keep the launchd registration for the next launch, but release the root
// process when no XPC client or session worker still needs it.
private var clients = 0
private func retireIfIdle() {
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
        workerLock.lock(); defer { workerLock.unlock() }
        guard clients == 0 else { return }
        if worker?.isRunning == true { retireIfIdle(); return }
        exit(EXIT_SUCCESS)
    }
}
private final class Endpoint: NSObject, PFControl {
    let uid: uid_t
    let pid: pid_t
    init(_ connection: NSXPCConnection) {
        uid = connection.effectiveUserIdentifier
        pid = connection.processIdentifier
    }
    func start(_ session: String, profile: Int, reply: @escaping (String) -> Void) {
        guard let uuid = UUID(uuidString: session), session == uuid.uuidString,
              (0...5).contains(profile), let user = getpwuid(uid) else {
            reply("Invalid session request."); return
        }
        let home = String(cString: user.pointee.pw_dir)
        let heartbeat = home + "/Library/Application Support/MoleDPI/Sessions/" + session + "/alive"
        run([String(uid), String(pid), session, heartbeat, String(profile), "v1"], wait: false, reply: reply)
    }
    func repair(_ session: String, reply: @escaping (String) -> Void) {
        guard let uuid = UUID(uuidString: session), session == uuid.uuidString else {
            reply("Invalid recovery session."); return
        }
        run(["--repair", String(uid), session], wait: true, reply: reply)
    }
    private func run(_ args: [String], wait: Bool, reply: @escaping (String) -> Void) {
        workerLock.lock(); defer { workerLock.unlock() }
        guard worker?.isRunning != true else { reply("A network worker is already running."); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PFService.root + "/moledpi-pf")
        process.arguments = args
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run(); worker = process
            if wait { process.waitUntilExit() }
            reply(wait && process.terminationStatus != 0 ? "Network recovery failed." : "")
        } catch { reply("Could not start the installed network worker.") }
    }
}

private final class Server: NSObject, NSXPCListenerDelegate {
    let owner: uid_t
    init(owner: uid_t) { self.owner = owner }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard c.effectiveUserIdentifier == owner else { return false }
        workerLock.lock(); clients += 1; workerLock.unlock()
        c.invalidationHandler = {
            workerLock.lock(); clients -= 1; workerLock.unlock()
            retireIfIdle()
        }
        c.exportedInterface = NSXPCInterface(with: PFControl.self)
        c.exportedObject = Endpoint(c)
        c.resume()
        return true
    }
}
@main struct Daemon {
    static func main() {
        let args = CommandLine.arguments
        guard geteuid() == 0, args.count == 3, let uid = uid_t(args[1]), uid >= 500,
              args[2].count == 40, args[2].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { exit(64) }
        let listener = NSXPCListener(machServiceName: PFService.name)
        listener.setConnectionCodeSigningRequirement("cdhash H\"\(args[2])\"")
        let server = Server(owner: uid); listener.delegate = server
        listener.resume()
        withExtendedLifetime((listener, server)) { dispatchMain() }
    }
}
