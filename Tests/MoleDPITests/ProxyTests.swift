// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import MoleDPI
final class ProxyTests: XCTestCase {
    func testCONNECTValidation() {
        XCTAssertEqual(Request.host(Data("CONNECT discord.com:443 HTTP/1.1\r\nHost: discord.com\r\n\r\n".utf8)), "discord.com")
        for request in ["GET https://discord.com/ HTTP/1.1\r\n\r\n", "CONNECT example.com:80 HTTP/1.1\r\n\r\n", "CONNECT a@evil.com:443 HTTP/1.1\r\n\r\n", "CONNECT :443 HTTP/1.1\r\n\r\n", "CONNECT example.com:443 HTTP/1.1\r\n"] {
            XCTAssertNil(Request.host(Data(request.utf8)))
        }
    }
    func testPortConflictAndRestart() async throws {
        let a = Proxy(); let b = Proxy()
        try await a.start()
        do { try await b.start(); XCTFail("Should reject occupied loopback port") } catch { }
        b.stop(); a.stop()
        try await a.start(); a.stop()
    }
    func testOptInLiveHTTPS() async throws {
        guard ProcessInfo.processInfo.environment["MOLE_LIVE_TEST"] == "1" else { throw XCTSkip("Set MOLE_LIVE_TEST=1 for external HTTPS test") }
        let proxy = Proxy(); try await proxy.start(); defer { proxy.stop() }
        let result = await Probe.check(host: "example.com", proxy: true)
        XCTAssertTrue(result)
    }
}
