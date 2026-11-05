// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum PFService {
    static let name = "local.moledpi.pf-service"
    static let root = "/Library/PrivilegedHelperTools/local.moledpi"
    static let plist = "/Library/LaunchDaemons/" + name + ".plist"
}

@objc(MolePFControl) protocol PFControl {
    func start(_ session: String, profile: Int, reply: @escaping (String) -> Void)
    func repair(_ session: String, reply: @escaping (String) -> Void)
}
