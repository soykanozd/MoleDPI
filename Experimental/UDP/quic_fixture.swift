// SPDX-License-Identifier: GPL-3.0-only
// Real QUIC transport fixture. Loopback only; temporary certificate pinning.
import Foundation
import Network
import Security

let args = CommandLine.arguments
let queue = DispatchQueue(label: "MoleDPI.QUIC.fixture")
func fail(_ text: String) -> Never { print("FAIL " + text); fflush(stdout); exit(1) }
guard args.count >= 3 else { fail("arguments") }
let quic = NWProtocolQUIC.Options(alpn: ["moledpi-lab"])
let params = NWParameters(quic: quic)
if args[1] == "server" {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath:args[2])) else { fail("identity input") }
    var imported: CFArray?
    let options = [kSecImportExportPassphrase as String:"local-test", kSecImportToMemoryOnly as String:true] as CFDictionary
    guard SecPKCS12Import(data as CFData, options, &imported) == errSecSuccess,
          let list = imported as? [[String:Any]], let entry = list.first,
          let identity = entry[kSecImportItemIdentity as String] else { fail("temporary identity import") }
    let secIdentity = unsafeBitCast(identity as CFTypeRef, to: SecIdentity.self)
    guard let local = sec_identity_create(secIdentity) else { fail("identity") }
    sec_protocol_options_set_local_identity(quic.securityProtocolOptions,local)
    params.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(args.count > 3 ? args[3] : "127.0.0.1"),port:.any)
    let listener = try NWListener(using:params)
    var connections: [NWConnection] = []
    listener.newConnectionHandler = { connection in
        connections.append(connection)
        connection.start(queue:queue)
        connection.receive(minimumIncompleteLength:1,maximumLength:65535) { data,_,_,error in
            if let data { connection.send(content:data,completion:.contentProcessed { _ in }) }
        }
    }
    listener.stateUpdateHandler = { state in
        switch state {
        case .ready: print("READY \(listener.port!.rawValue)");fflush(stdout)
        case .failed: fail("listener")
        default: break
        }
    }
    listener.start(queue:queue)
} else {
    guard (args.count == 4 || args.count == 5), let port = UInt16(args[2]), let expected = try? Data(contentsOf:URL(fileURLWithPath:args[3])) else { fail("client input") }
    sec_protocol_options_set_tls_server_name(quic.securityProtocolOptions,"localhost")
    sec_protocol_options_set_verify_block(quic.securityProtocolOptions,{ _,trust,complete in
        let reference = sec_trust_copy_ref(trust).takeRetainedValue()
        let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate]
        complete(chain?.first.map { SecCertificateCopyData($0) as Data == expected } ?? false)
    },queue)
    let connection=NWConnection(host:NWEndpoint.Host(args.count == 5 ? args[4] : "127.0.0.1"),port:NWEndpoint.Port(rawValue:port)!,using:params)
    let content=Data("MoleDPI real QUIC echo".utf8)
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            connection.send(content:content,completion:.contentProcessed { error in
                if error != nil { fail("QUIC send") }
            })
            connection.receive(minimumIncompleteLength:content.count,maximumLength:65535) { data,_,_,error in
                guard data == content else { fail("QUIC echo") }
                print("PASS real QUIC handshake and stream echo with pinned test certificate");fflush(stdout)
                connection.cancel();exit(0)
            }
        case .failed: fail("QUIC connection")
        default: break
        }
    }
    connection.start(queue:queue)
}
queue.asyncAfter(deadline:.now()+(args[1] == "server" ? 120 : 15)) { fail("QUIC fixture timeout") }
dispatchMain()
