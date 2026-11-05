// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import Darwin

enum EncryptedDNS {
    static let suffixes = ["discord.com", "discord.gg", "discordapp.com", "discordapp.net", "roblox.com", "rbxcdn.com"]
    static func question(_ data: Data) -> String? {
        let b = [UInt8](data)
        guard b.count >= 17, b.count <= 4096, b[2] & 0x80 == 0, b[4] == 0, b[5] == 1 else { return nil }
        var i = 12, labels: [String] = []
        while i < b.count {
            let n = Int(b[i]); i += 1
            if n == 0 { break }
            guard n <= 63, i+n < b.count,
                  let label = String(bytes:b[i..<i+n], encoding:.ascii) else { return nil }
            labels.append(label.lowercased()); i += n
        }
        guard i+4 <= b.count, b[i+2] == 0, b[i+3] == 1 else { return nil }
        let name = labels.joined(separator: ".")
        return suffixes.contains(where: { name == $0 || name.hasSuffix("."+$0) }) ? name : nil
    }
    static func request(_ query: Data) async -> Data? {
        guard question(query) != nil else { return nil }
        let token = query.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        let p = Process(), output = Pipe()
        p.executableURL = URL(fileURLWithPath:"/usr/bin/curl")
        p.arguments = ["--disable","--silent","--fail","--proxy","","--noproxy","*",
                       "--resolve","dns.quad9.net:443:9.9.9.9","--connect-timeout","3","--max-time","5",
                       "--max-filesize","65535","--header","Accept: application/dns-message",
                       "https://dns.quad9.net/dns-query?dns="+token]
        p.standardOutput = output; p.standardError = FileHandle.nullDevice
        // Drain while curl runs so a larger DNS answer cannot fill its pipe.
        async let body = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        do { try await OwnedCommand(p).run() } catch {
            try? output.fileHandleForWriting.close()
            _ = await body
            return nil
        }
        let data = await body
        guard p.terminationStatus == 0, data.count >= 12, data.count <= 65535,
              data[0] == query[0], data[1] == query[1], data[2] & 0x80 != 0 else { return nil }
        return data
    }
    static func lookup(_ host: String) async -> String? {
        guard suffixes.contains(where: { host == $0 || host.hasSuffix("."+$0) }) else { return nil }
        var q = Data([0x4d,0x44,1,0,0,1,0,0,0,0,0,0])
        for label in host.split(separator:".") { q.append(UInt8(label.utf8.count)); q.append(contentsOf:label.utf8) }
        q.append(contentsOf:[0,0,1,0,1])
        guard let reply = await request(q) else { return nil }
        let b = [UInt8](reply)
        func endName(_ start: Int) -> Int? {
            var i = start
            for _ in 0..<128 {
                guard i < b.count else { return nil }
                let n = Int(b[i]); i += 1
                if n == 0 { return i }
                if n & 0xc0 == 0xc0 { return i < b.count ? i+1 : nil }
                guard n <= 63 else { return nil }; i += n
            }
            return nil
        }
        guard let end = endName(12) else { return nil }
        var i = end+4
        let count = min(128,Int(b[6])*256+Int(b[7]))
        for _ in 0..<count {
            guard let end = endName(i), end+10 <= b.count else { return nil }
            let n = Int(b[end+8])*256+Int(b[end+9]); i = end+10
            guard i+n <= b.count else { return nil }
            if b[end] == 0 && b[end+1] == 1 && b[end+2] == 0 && b[end+3] == 1 && n == 4 {
                return b[i..<i+4].map(String.init).joined(separator:".")
            }
            i += n
        }
        return nil
    }
}

// Session-only loopback UDP/TCP DNS bridge. No plaintext upstream fallback.
final class DNSRelay: @unchecked Sendable {
    private let queue = DispatchQueue(label:"MoleDPI.encrypted-dns")
    private let lock = NSLock()
    private var ready = 0
    private var listeners: [NWListener] = []
    private var clients: [UUID: NWConnection] = [:]
    private var tasks: [UUID: Task<Void,Never>] = [:]
    func start() async throws {
        for tcp in [false,true] {
            let params: NWParameters = tcp ? .tcp : .udp
            params.requiredLocalEndpoint = .hostPort(host:"127.0.0.1", port:18083)
            let listener = try NWListener(using:params)
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state { self?.lock.lock(); self?.ready += 1; self?.lock.unlock() }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection,tcp:tcp) }
            listeners.append(listener); listener.start(queue:queue)
        }
        for _ in 0..<100 {
            try Task.checkCancellation()
            if isReady() { return }
            try await Task.sleep(nanoseconds:20_000_000)
        }
        throw RoutingError.message("The encrypted DNS listener could not start.")
    }
    private func isReady() -> Bool { lock.lock(); defer { lock.unlock() }; return ready == 2 }
    func stop() {
        queue.sync {
            listeners.forEach { $0.cancel() }; listeners.removeAll()
            tasks.values.forEach { $0.cancel() }; tasks.removeAll()
            clients.values.forEach { $0.cancel() }; clients.removeAll()
        }
    }
    private func accept(_ c: NWConnection,tcp: Bool) {
        guard clients.count < 24 else { c.cancel(); return }
        let id = UUID(); clients[id] = c
        c.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.remove(id) }
            if case .cancelled = state { self?.remove(id) }
        }
        c.start(queue:queue)
        if tcp { receiveTCP(c,id:id,buffer:Data()) }
        else { c.receiveMessage { [weak self] data,_,_,_ in self?.answer(data,c:c,id:id,tcp:false) } }
        queue.asyncAfter(deadline:.now()+8) { [weak self] in self?.clients[id]?.cancel() }
    }
    private func remove(_ id: UUID) { clients.removeValue(forKey:id); tasks.removeValue(forKey:id)?.cancel() }
    private func receiveTCP(_ c:NWConnection,id:UUID,buffer:Data) {
        c.receive(minimumIncompleteLength:1,maximumLength:4098) { [weak self] data,_,done,error in
            var bytes = buffer; if let data { bytes.append(data) }
            guard error == nil, !bytes.isEmpty else { c.cancel(); return }
            if bytes.count >= 2 {
                let n = Int(bytes[0])*256+Int(bytes[1])
                guard n >= 12, n <= 4096, bytes.count <= n+2 else { c.cancel(); return }
                if bytes.count == n+2 { self?.answer(Data(bytes.dropFirst(2)),c:c,id:id,tcp:true); return }
            }
            if done { c.cancel() } else { self?.receiveTCP(c,id:id,buffer:bytes) }
        }
    }
    private func answer(_ query:Data?,c:NWConnection,id:UUID,tcp:Bool) {
        guard let query, EncryptedDNS.question(query) != nil else { c.cancel(); return }
        tasks[id] = Task { [weak self] in
            let reply = await EncryptedDNS.request(query)
            self?.queue.async {
                guard self?.clients[id] != nil, let reply else { c.cancel(); return }
                var wire = Data()
                if tcp { wire.append(contentsOf:[UInt8(reply.count >> 8), UInt8(reply.count & 255)]) }
                wire.append(reply)
                c.send(content:wire,completion:.contentProcessed { _ in c.cancel() })
            }
        }
    }
}
