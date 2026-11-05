import Foundation
@main struct Reject {
    static func main() {
        let c = NSXPCConnection(machServiceName: PFService.name, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: PFControl.self)
        c.resume()
        let proxy = c.remoteObjectProxyWithErrorHandler { error in
            print("PASS: unauthorized XPC client rejected: " + error.localizedDescription); exit(0)
        } as! PFControl
        proxy.start("invalid", profile: -1) { _ in print("FAIL: unauthorized request reached exported object"); exit(1) }
        DispatchQueue.global().asyncAfter(deadline: .now()+5) { print("FAIL: no definite XPC result"); exit(2) }
        RunLoop.current.run()
    }
}
