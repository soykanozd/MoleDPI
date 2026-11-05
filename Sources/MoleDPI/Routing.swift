// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security
import SystemConfiguration

protocol Routing: Sendable {
    func enable() async throws
    func restore() async throws
    func isActive() async -> Bool
}
enum RoutingError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
// An actor serializes enable/restore so cancellation cannot race a network write.
actor SystemRouting: Routing {
    static let journalURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MoleDPI/proxy-recovery.plist")
    static let keys = ["HTTPSEnable", "HTTPSProxy", "HTTPSPort"]
    private var authorization: AuthorizationRef?
    deinit { if let authorization { AuthorizationFree(authorization, []) } }

    static func primaryID() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MoleDPI" as CFString, nil, nil) else { return nil }
        for family in ["IPv4", "IPv6"] {
            if let info = SCDynamicStoreCopyValue(store, "State:/Network/Global/\(family)" as CFString) as? [String: Any],
               let service = info["PrimaryService"] as? String { return service }
        }
        return nil
    }
    private func preferences() throws -> SCPreferences {
        if authorization == nil {
            var auth: AuthorizationRef?
            let status = "system.preferences.network".withCString { name in
                var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                return withUnsafeMutablePointer(to: &item) { pointer in
                    var rights = AuthorizationRights(count: 1, items: pointer)
                    return AuthorizationCreate(&rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], &auth)
                }
            }
            guard status == errAuthorizationSuccess, let auth else {
                throw RoutingError.message("Mac ağ izni verilmedi. Bağlantı açılmadı.")
            }
            authorization = auth
        }
        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "MoleDPI" as CFString, nil, authorization) else {
            throw RoutingError.message("Mac ağ ayarları açılamadı.")
        }
        return prefs
    }
    private func proxyProtocol(_ prefs: SCPreferences, serviceID: String) throws -> SCNetworkProtocol {
        guard let service = SCNetworkServiceCopy(prefs, serviceID as CFString),
              let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else {
            throw RoutingError.message("Etkin ağın HTTPS proxy ayarı bulunamadı.")
        }
        return proto
    }
    static func owns(_ config: [String: Any]) -> Bool {
        (config["HTTPSEnable"] as? NSNumber)?.intValue == 1 &&
        config["HTTPSProxy"] as? String == "127.0.0.1" &&
        (config["HTTPSPort"] as? NSNumber)?.intValue == 18080
    }
    static func restored(current: [String: Any], saved: [String: Any]) -> [String: Any] {
        var config = current
        for key in keys { config[key] = saved[key] }
        return config
    }
    func enable() throws {
        // A crash/relaunch can leave settings behind. Restore journal before reusing.
        if FileManager.default.fileExists(atPath: Self.journalURL.path) { try restore() }
        guard let serviceID = Self.primaryID() else { throw RoutingError.message("Etkin Wi-Fi veya Ethernet bağlantısı bulunamadı.") }
        let prefs = try preferences()
        guard SCPreferencesLock(prefs, true) else { throw RoutingError.message("Ağ ayarları başka bir işlem tarafından kullanılıyor.") }
        defer { SCPreferencesUnlock(prefs) }
        let proto = try proxyProtocol(prefs, serviceID: serviceID)
        var config = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
        for key in ["HTTPSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable", "HTTPSRequiresPassword"] {
            if (config[key] as? NSNumber)?.intValue == 1 {
                throw RoutingError.message("Mevcut proxy / otomatik proxy ayarın var. Üzerine yazılmadı.")
            }
        }
        var saved: [String: Any] = [:]
        for key in Self.keys { saved[key] = config[key] }
        let journal: [String: Any] = ["serviceID": serviceID, "saved": saved]
        try FileManager.default.createDirectory(at: Self.journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: journal, format: .xml, options: 0)
        try data.write(to: Self.journalURL, options: .atomic)
        config["HTTPSEnable"] = 1; config["HTTPSProxy"] = "127.0.0.1"; config["HTTPSPort"] = 18080
        guard SCNetworkProtocolSetConfiguration(proto, config as CFDictionary), SCPreferencesCommitChanges(prefs), SCPreferencesApplyChanges(prefs) else {
            // Keep recovery journal: commit may have succeeded even if apply failed.
            throw RoutingError.message("HTTPS proxy uygulanamadı. Ağ ayarını onarmak için Yeniden Dene'yi kullan.")
        }
    }
    func restore() throws {
        guard FileManager.default.fileExists(atPath: Self.journalURL.path) else { return }
        let data = try Data(contentsOf: Self.journalURL)
        guard let journal = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let serviceID = journal["serviceID"] as? String,
              let saved = journal["saved"] as? [String: Any] else { throw RoutingError.message("Ağ kurtarma kaydı okunamadı. HTTPS proxy ayarını elle denetle.") }
        let prefs = try preferences()
        guard SCPreferencesLock(prefs, false) else { throw RoutingError.message("Ağ ayarları kilitli; yeniden dene.") }
        defer { SCPreferencesUnlock(prefs) }
        let proto = try proxyProtocol(prefs, serviceID: serviceID)
        let config = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
        if Self.owns(config) {
            let old = Self.restored(current: config, saved: saved)
            guard SCNetworkProtocolSetConfiguration(proto, old as CFDictionary), SCPreferencesCommitChanges(prefs), SCPreferencesApplyChanges(prefs) else {
                throw RoutingError.message("HTTPS proxy geri alınamadı. Ağ → Proxy'ler bölümünden kapatabilirsin.")
            }
        } else {
            // Someone changed these settings. Never overwrite their new configuration.
            // If commit failed originally, the prior configuration is already intact.
        }
        try FileManager.default.removeItem(at: Self.journalURL)
    }
    func isActive() -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "MoleDPI" as CFString, nil, nil),
              let proxies = SCDynamicStoreCopyProxies(store) as? [String: Any] else { return false }
        return Self.owns(proxies)
    }
}
