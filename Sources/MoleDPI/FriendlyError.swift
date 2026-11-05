// SPDX-License-Identifier: GPL-3.0-only
import Foundation
enum FriendlyError {
    static func message(_ error: Error) -> String {
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
