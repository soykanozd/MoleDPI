// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security

struct HelperApprovalDenied: LocalizedError {
    var errorDescription: String? { "Network helper approval was declined or failed." }
}

struct WorkerStartRejected: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

// XPC can fail, time out or deliver a delayed reply. Resume its waiter once.
final class ServiceReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void,Error>?
    private var timeout: DispatchWorkItem?
    init(_ continuation: CheckedContinuation<Void,Error>) { self.continuation = continuation }
    func arm(seconds: TimeInterval) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        let item = DispatchWorkItem { self.finish(RoutingError.message("Network helper reply timed out. Retry cleanup before quitting.")) }
        timeout = item; lock.unlock()
        DispatchQueue.global().asyncAfter(deadline:.now()+seconds,execute:item)
    }
    func finish(_ error: Error? = nil) {
        lock.lock()
        let pending = continuation; continuation = nil
        let item = timeout; timeout = nil
        lock.unlock(); item?.cancel()
        if let error { pending?.resume(throwing:error) } else { pending?.resume() }
    }
}

enum ServiceClient {
    static let names = ["moledpi-service", "moledpi-pf", "tpws", "ciadpi", "tunnel-runner", "moledpi-udp"]
    static func hex(_ value: String?, length: Int) throws -> String {
        guard let value, value.count == length,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw RoutingError.message("Invalid signed helper manifest. Rebuild MoleDPI.")
        }
        return value
    }
    static func identity() throws -> (String, [String: Any]) {
        var code: SecCode?
        var disk: SecStaticCode?
        var info: CFDictionary?
        var result = SecCodeCopySelf([], &code)
        guard result == errSecSuccess, let code else { throw RoutingError.message("Running code lookup failed: \(result)") }
        result = SecCodeCopyStaticCode(code, [], &disk)
        guard result == errSecSuccess, let disk else { throw RoutingError.message("Static code lookup failed: \(result)") }
        result = SecStaticCodeCheckValidity(disk, [], nil)
        guard result == errSecSuccess else { throw RoutingError.message("Installed code verification failed: \(result)") }
        result = SecCodeCheckValidity(code, [], nil)
        guard result == errSecSuccess else { throw RoutingError.message("Running code verification failed: \(result)") }
        result = SecCodeCopySigningInformation(disk, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard result == errSecSuccess, let manifest = (info as NSDictionary?)?[kSecCodeInfoPList] as? [String:Any],
              let digest = (info as NSDictionary?)?[kSecCodeInfoUnique] as? Data else {
            throw RoutingError.message("Signed manifest lookup failed: \(result)")
        }
        return (try hex(digest.map { String(format: "%02x", $0) }.joined(), length: 40), manifest)
    }

    // The only authorization prompt. Install an exact, hash-pinned local build.
    // Changes to either peer require explicit approval again.
    static func prepare() async throws -> String {
        guard Bundle.main.bundleURL.path == "/Applications/MoleDPI.app",
              let resources = Bundle.main.resourceURL else {
            throw RoutingError.message("Open the installed copy in /Applications to configure MoleDPI.")
        }
        let (clientHash, info) = try identity()
        let serverHash = try hex(info["MoleServiceCDHash"] as? String, length: 40)
        let args = [PFService.root + "/moledpi-service", String(getuid()), clientHash]
        let manifest: [String: Any] = ["Label": PFService.name, "ProgramArguments": args,
            "ThrottleInterval": 1, "MachServices": [PFService.name: true], "AssociatedBundleIdentifiers": ["local.moledpi.app"]]
        let data = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        let installed = URL(fileURLWithPath: PFService.plist)
        if let current = try? Data(contentsOf: installed),
           let plist = try? PropertyListSerialization.propertyList(from: current, format: nil) as? NSDictionary,
           plist.isEqual(to: manifest) { return serverHash }

        let q = PFConnection.shellQuote
        var script = """
        set -eu
        export PATH=/usr/bin:/bin:/usr/sbin:/sbin
        umask 077
        for d in /Library /Library/LaunchDaemons /Library/PrivilegedHelperTools /Library/PrivilegedHelperTools/local.moledpi; do
          if [ ! -e "$d" ]; then mkdir -m 755 "$d"; fi
          [ ! -L "$d" ] && [ -d "$d" ] && [ "$(stat -f '%u:%Lp' "$d")" = '0:755' ] || exit 73
          case "$(ls -lde "$d" | head -1 | cut -d' ' -f1)" in *+*) exit 73;; esac
        done
        ! pgrep -x moledpi-pf >/dev/null || exit 75
        commands=$(ps -axo comm=) || exit 70
        for n in moledpi-pf moledpi-udp tpws ciadpi tunnel-runner; do
          if printf '%s\\n' "$commands" | grep -Fqx "/Library/PrivilegedHelperTools/local.moledpi/$n"; then exit 75; fi
        done
        tmp=$(mktemp -d /private/var/root/moledpi.XXXXXXXX)
        trap 'rm -rf "$tmp"' EXIT
        """ + "\n"
        for name in names {
            let expected = try hex(info["MoleSHA-" + name] as? String, length: 64)
            // Hash only after copying into root-private staging to close replacement races.
            script += """
            /bin/cp \(q(resources.appendingPathComponent(name).path)) "$tmp/\(name)"
            [ "$(shasum -a 256 "$tmp/\(name)" | cut -d' ' -f1)" = \(q(expected)) ] || exit 65
            """ + "\n"
        }
        script += """
        printf '%s' \(q(data.base64EncodedString())) | base64 -D > "$tmp/service.plist"
        if launchctl print system/\(PFService.name) >/dev/null 2>&1; then
          launchctl bootout system/\(PFService.name)
        fi
        for n in moledpi-service moledpi-pf tpws ciadpi tunnel-runner moledpi-udp; do
          install -S -o root -g wheel -m 755 "$tmp/$n" \(q(PFService.root))/"$n"
        done
        install -S -o root -g wheel -m 644 "$tmp/service.plist" \(q(PFService.plist))
        if ! launchctl bootstrap system \(q(PFService.plist)); then rm -f \(q(PFService.plist)); exit 70; fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script " + PFConnection.appleScriptString(script) +
            " with prompt \"Install or update MoleDPI’s local network helper. This approval applies to this build.\" with administrator privileges"]
        process.standardOutput = FileHandle.nullDevice
        try await OwnedCommand(process).run()
        guard process.terminationStatus == 0 else {
            throw HelperApprovalDenied()
        }
        return serverHash
    }
    static func connect(serverHash: String) -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: PFService.name, options: .privileged)
        c.setCodeSigningRequirement("cdhash H\"\(serverHash)\"")
        c.remoteObjectInterface = NSXPCInterface(with: PFControl.self)
        c.resume()
        return c
    }
    static func request(_ c: NSXPCConnection, session: String, profile: Int?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let pending = ServiceReply(continuation)
            pending.arm(seconds:profile == nil ? 50 : 10)
            let proxy = c.remoteObjectProxyWithErrorHandler { error in pending.finish(error) }
            guard let remote = proxy as? PFControl else {
                pending.finish(RoutingError.message("Network helper is unavailable.")); return
            }
            let reply: (String) -> Void = { error in
                if error.isEmpty { pending.finish() }
                else if profile != nil { pending.finish(WorkerStartRejected(reason:error)) }
                else { pending.finish(RoutingError.message(error)) }
            }
            if let profile { remote.start(session, profile: profile, reply: reply) }
            else { remote.repair(session, reply: reply) }
        }
    }
}
