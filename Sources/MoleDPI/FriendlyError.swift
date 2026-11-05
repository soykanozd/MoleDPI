// SPDX-License-Identifier: GPL-3.0-only
import Foundation
// Only fixed categories and guidance cross into the UI; no destinations or raw errors.
enum ConnectionIssue: String, Error, LocalizedError, Sendable {
    case offline, dns, localEngine, timeout, secureAccess, remoteResponse, accessUnverified
    var errorDescription: String? { message }
    var message: String {
        switch self {
        case .offline: return "No internet connection. Waiting for the network."
        case .dns: return "A name lookup failed. Check your DNS or try another network."
        case .localEngine: return "The local network engine is unavailable. Retry the connection."
        case .timeout: return "The access check timed out. Check your network and retry."
        case .secureAccess: return "A secure connection failed. Check the date and other network tools."
        case .remoteResponse: return "A check website returned an error. Retry later."
        case .accessUnverified: return "Access could not be verified. Try another network."
        }
    }
    var guidance: String {
        switch self {
        case .offline: return "Connect to Wi-Fi or Ethernet. Complete any network sign-in page. MoleDPI waits without starting new workers while offline."
        case .dns: return "A control destination could not be resolved. Check system DNS settings and network sign-in. Recovery DNS covers only a limited set of domains; it is not a replacement for all system DNS."
        case .localEngine: return "Retry after disconnecting. Check for another local proxy or firewall using the same ports. If cleanup fails, use Repair Network before quitting."
        case .timeout: return "The check did not finish within its time limit. This can be caused by a slow network, a firewall or access restrictions. Try another network; a timeout alone does not identify censorship."
        case .secureAccess: return "Keep certificate validation enabled. Check the Mac date and time, network sign-in and other security or proxy software. A TLS failure alone does not identify censorship."
        case .remoteResponse: return "The remote server responded but did not pass the HTTPS check. A website outage or policy can cause this; it does not prove the local engine failed."
        case .accessUnverified: return "The available checks did not verify access. A firewall, network outage, remote website or filtering can cause this. MoleDPI cannot reliably distinguish all of them."
        }
    }
    static func curlExit(_ status: Int32) -> ConnectionIssue? {
        switch status {
        case 0: return nil
        case 5, 6: return .dns
        case 7: return .accessUnverified
        case 22: return .remoteResponse
        case 28: return .timeout
        case 35, 51, 58, 60, 77, 80, 82, 83, 90, 91: return .secureAccess
        default: return .accessUnverified
        }
    }
    static func summarize(_ sites: [SiteCheck]) -> ConnectionIssue {
        let failed = sites.filter { $0.reachable != true }
        let failures = failed.compactMap(\.failure)
        guard failures.count == failed.count, let first = failures.first, failures.allSatisfy({ $0 == first }) else { return .accessUnverified }
        return first
    }
}
enum FriendlyError {
    static func message(_ error: Error) -> String {
        if let issue = error as? ConnectionIssue { return issue.message }
        if error is HelperApprovalDenied { return "Permission was not approved. Click Connect to try again." }
        if error is CancellationError { return "Connection cancelled." }
        if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
            return "No internet connection. Waiting for the network."
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("dns") { return "DNS recovery is unavailable. Check your internet connection and try again." }
        if text.contains("cleanup") || text.contains("recovery") || text.contains("onar") {
            return "Network cleanup needs attention. Retry before quitting."
        }
        if text.contains("port") || text.contains("listener") || text.contains("probe did not") {
            return "A local network listener is unavailable. Close other network tools and retry."
        }
        if text.contains("signature") || text.contains("code verification") || text.contains("manifest") {
            return "The application could not be verified. Reinstall a trusted copy."
        }
        if text.contains("https") || text.contains("verify") || text.contains("doğrula") {
            return "Secure access could not be verified. Retrying safely."
        }
        return "Connection failed. Check your network and try again."
    }
}
