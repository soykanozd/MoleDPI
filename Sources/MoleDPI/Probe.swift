// SPDX-License-Identifier: GPL-3.0-only
import Foundation
struct Probe {
    enum Transport: Sendable { case direct, http, socks }
    // Diagnostics use only fixed public service names. TLS still verifies the original name.
    static func alternateAddress(_ host: String) async -> String? {
        guard ["discord.com", "www.roblox.com"].contains(host) else { return nil }
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        p.arguments = ["+short", "+time=2", "+tries=1", "@9.9.9.9", "-p", "9953", host, "A"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try await OwnedCommand(p).run() } catch { return nil }
        let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(whereSeparator: \.isNewline)
        return lines.map(String.init).first { var ip = in_addr(); return inet_pton(AF_INET, $0, &ip) == 1 }
    }
    static func check(host: String, proxy: Bool) async -> Bool { await check(host: host, using: proxy ? .http : .direct) }

    static func check(host: String, using transport: Transport, address: String? = nil) async -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        let proxy: String
        switch transport { case .direct: proxy = ""; case .http: proxy = "http://127.0.0.1:18080"; case .socks: proxy = "socks5h://127.0.0.1:18081" }
        p.arguments = ["--disable", "--silent", "--fail", "--output", "/dev/null", "--connect-timeout", "5", "--max-time", "10", "--noproxy", proxy.isEmpty ? "*" : "", "--proxy", proxy, "https://\(host)/"]
        if let address {
            p.arguments?.append(contentsOf: ["--connect-to", "\(host):443:\(address):443"])
        }
        let timing = ConnectClock.enabled ? Pipe() : nil
        if let timing {
            p.arguments?.append(contentsOf: ["--write-out", "%{time_namelookup}"])
            p.standardOutput = timing
        } else { p.standardOutput = FileHandle.nullDevice }
        p.standardError = FileHandle.nullDevice
        do {
            try await OwnedCommand(p).run()
            if let timing, let seconds = Double(String(decoding: timing.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) {
                print(String(format: "TIMING curl.local-name-lookup %.2f ms", seconds * 1000))
            }
            if ConnectClock.enabled && p.terminationStatus != 0 { print("PROBE exit=\(p.terminationStatus)") }
            return p.terminationStatus == 0
        } catch { return false }
    }
}
