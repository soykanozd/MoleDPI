// SPDX-License-Identifier: GPL-3.0-only
import Darwin

// Inspect only the child process's own sockets. A listener owned by another
// program on the same port must never make the connectivity gate succeed.
enum ListenerReadiness {
    static func ownsTCPListener(pid: pid_t, port: UInt16) -> Bool {
        guard pid > 1 else { return false }
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0))
        guard needed > 0, needed <= 1_048_576 else { return false }
        var entries = [proc_fdinfo](repeating: proc_fdinfo(), count: needed / stride + 8)
        let bytes = entries.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard bytes > 0 else { return false }
        for fd in entries.prefix(Int(bytes) / stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var socket = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socket, size) == size,
                  socket.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = socket.psi.soi_proto.pri_tcp
            if tcp.tcpsi_state == TSI_S_LISTEN && UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)) == port { return true }
        }
        return false
    }
}
