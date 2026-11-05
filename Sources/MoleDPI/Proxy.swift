// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network

// Deliberately small, auditable CONNECT-only proxy. No TLS interception.
enum Request {
    static func host(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              text.hasSuffix("\r\n\r\n") else { return nil }
        let words = text.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard words.count == 3, words[0] == "CONNECT", words[2] == "HTTP/1.1" || words[2] == "HTTP/1.0" else { return nil }
        let authority = String(words[1])
        guard authority.hasSuffix(":443") else { return nil }
        let host = String(authority.dropLast(4))
        guard !host.isEmpty, host.count <= 253,
              host.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return host
    }
}
// All mutable state is confined to queue; stop synchronizes on it.
enum TLSFragment {
    // Split a complete TLS handshake record inside the requested SNI when found.
    // TLS handshake bytes remain identical; only record framing changes.
    static func split(_ data: Data, host: String) -> (Data, Int)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6, bytes[0] == 22, bytes[1] == 3 else { return nil }
        let length = Int(bytes[3]) * 256 + Int(bytes[4])
        guard length > 1, length <= 18432, bytes.count >= length + 5 else { return nil }
        let body = Data(bytes[5..<(5 + length)])
        let at = body.range(of: Data(host.utf8)).map { body.distance(from: body.startIndex, to: $0.lowerBound) + 1 } ?? 1
        guard at < length else { return nil }
        func record(_ payload: Data) -> Data {
            Data([22, bytes[1], bytes[2], UInt8(payload.count >> 8), UInt8(payload.count & 255)]) + payload
        }
        let first = record(Data(body.prefix(at)))
        return (first + record(Data(body.dropFirst(at))) + Data(bytes.dropFirst(5 + length)), first.count)
    }
}
final class Proxy: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MoleDPI.proxy")
    private var listener: NWListener?
    private var peers: [UUID: Peer] = [:]
    func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
                    let params = NWParameters(tls: nil, tcp: tcp)
                    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 18080)
                    let l = try NWListener(using: params)
                    self.listener = l
                    var resumed = false
                    l.stateUpdateHandler = { state in
                        if case .ready = state, !resumed { resumed = true; c.resume() }
                        if case .failed(let error) = state, !resumed { resumed = true; c.resume(throwing: error) }
                        if case .cancelled = state, !resumed { resumed = true; c.resume(throwing: CancellationError()) }
                    }
                    l.newConnectionHandler = { client in
                        guard self.peers.count < 128 else { client.cancel(); return }
                        let id = UUID()
                        let peer = Peer(client, queue: self.queue) { self.peers.removeValue(forKey: id) }
                        self.peers[id] = peer; peer.start()
                    }
                    l.start(queue: self.queue)
                } catch { c.resume(throwing: error) }
            }
        }
    }
    func stop() {
        queue.sync {
            listener?.cancel(); listener = nil
            let active = Array(peers.values)
            active.forEach { $0.close() }; peers.removeAll()
        }
    }
}
private final class Peer {
    let client: NWConnection
    var remote: NWConnection?
    let queue: DispatchQueue
    let done: () -> Void
    var closed = false
    var header = Data()
    var first = true
    var hello = Data()
    var targetHost = ""
    var timer: DispatchSourceTimer?
    init(_ client: NWConnection, queue: DispatchQueue, done: @escaping () -> Void) {
        self.client = client; self.queue = queue; self.done = done
    }
    func start() {
        client.start(queue: queue)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15)
        timer.setEventHandler { [weak self] in self?.close() }
        timer.resume(); self.timer = timer
        readHeader()
    }
    func close() {
        guard !closed else { return }; closed = true
        timer?.cancel(); timer = nil
        client.cancel(); remote?.cancel(); done()
    }
    func readHeader() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, end, error in
            guard !closed, error == nil, let data, !data.isEmpty else { close(); return }
            header.append(data)
            guard header.count <= 8192 else { close(); return }
            if let range = header.range(of: Data("\r\n\r\n".utf8)) {
                // Reject pipelined payload rather than silently dropping bytes.
                guard range.upperBound == header.endIndex, let host = Request.host(header) else { close(); return }
                connect(host)
            } else if end { close() } else { readHeader() }
        }
    }
    func connect(_ host: String) {
        targetHost = host
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let upstream = NWConnection(host: NWEndpoint.Host(host), port: 443, using: NWParameters(tls: nil, tcp: tcp))
        remote = upstream
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                self.client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { error in
                    guard error == nil else { self.close(); return }
                    self.timer?.schedule(deadline: .now() + 300)
                    self.pump(self.client, upstream, outbound: true)
                    self.pump(upstream, self.client, outbound: false)
                })
            case .failed: self.close()
            default: break
            }
        }
        upstream.start(queue: queue)
    }
    func pump(_ from: NWConnection, _ to: NWConnection, outbound: Bool) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, end, error in
            guard !closed, error == nil else { close(); return }
            guard let data, !data.isEmpty else { close(); return }
            timer?.schedule(deadline: .now() + 300)
            let next: (NWError?) -> Void = { error in
                if error != nil || end { self.close() }
                else { self.pump(from, to, outbound: outbound) }
            }
            if outbound && first {
                hello.append(data)
                guard hello.count <= 65536 else { close(); return }
                let bytes = [UInt8](hello)
                guard bytes.count >= 5 else { if end { close() } else { pump(from, to, outbound: true) }; return }
                let length = Int(bytes[3]) * 256 + Int(bytes[4])
                guard bytes[0] == 22, bytes[1] == 3, length <= 18432 else { close(); return }
                guard hello.count >= length + 5 else { if end { close() } else { pump(from, to, outbound: true) }; return }
                guard let (payload, at) = TLSFragment.split(hello, host: targetHost) else { close(); return }
                first = false; hello.removeAll()
                // Record fragmentation is real; TCP segmentation is best effort.
                to.send(content: Data(payload.prefix(at)), completion: .contentProcessed { error in
                    guard error == nil else { self.close(); return }
                    self.queue.asyncAfter(deadline: .now() + .milliseconds(20)) {
                        guard !self.closed else { return }
                        to.send(content: Data(payload.dropFirst(at)), completion: .contentProcessed(next))
                    }
                })
            } else { to.send(content: data, completion: .contentProcessed(next)) }
        }
    }
}
