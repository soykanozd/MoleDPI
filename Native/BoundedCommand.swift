// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

struct NativeCommandError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// Fixed-command callers supply small configuration/status data, never packets.
// Drain without blocking, bound output and execution, and signal only our child.
enum BoundedCommand {
    static func stop(pid: Int32, executable: String, grace seconds:TimeInterval = 2) -> Bool {
        guard pid > 1 else { return false }
        func matches() -> Bool? {
            var bytes = [UInt8](repeating:0,count:4096)
            let size = proc_pidpath(pid,&bytes,UInt32(bytes.count))
            if size > 0 { return String(decoding:bytes.prefix(Int(size)).prefix(while:{$0 != 0}),as:UTF8.self) == executable }
            if kill(pid,0) == -1 && errno == ESRCH { return false }
            return nil
        }
        guard let initial = matches() else { return false }
        guard initial else { return true } // This PID is gone or belongs to another executable.
        kill(pid,SIGTERM)
        let grace = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1_000_000_000)
        while matches() == true && DispatchTime.now().uptimeNanoseconds < grace { Thread.sleep(forTimeInterval:0.02) }
        if matches() == true { kill(pid,SIGKILL) }
        let end = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while matches() == true && DispatchTime.now().uptimeNanoseconds < end { Thread.sleep(forTimeInterval:0.02) }
        return matches() == false
    }
    static func run(_ executable: String, _ arguments: [String], input: String? = nil,
                    timeout: TimeInterval = 5, outputLimit: Int = 262144) throws -> (Int32, String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        process.environment = ["PATH":"/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL":"C"]
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd,F_GETFL)
        guard flags >= 0, fcntl(fd,F_SETFL,flags | O_NONBLOCK) == 0 else { throw NativeCommandError("Could not prepare local command output.") }
        var writer: Pipe?
        if let input {
            guard input.utf8.count <= 8192 else { throw NativeCommandError("Local command input is too large.") }
            let channel = Pipe(); writer = channel; process.standardInput = channel
        } else { process.standardInput = FileHandle.nullDevice }
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        try process.run()
        try? pipe.fileHandleForWriting.close()
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0.01,timeout) * 1_000_000_000)
        func stop() {
            if process.isRunning { process.terminate() }
            let grace = DispatchTime.now().uptimeNanoseconds + 300_000_000
            while process.isRunning && DispatchTime.now().uptimeNanoseconds < grace { Thread.sleep(forTimeInterval:0.01) }
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            let end = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            while process.isRunning && DispatchTime.now().uptimeNanoseconds < end { Thread.sleep(forTimeInterval:0.01) }
        }
        do {
            if let input, let writer {
                try? writer.fileHandleForReading.close()
                let target = writer.fileHandleForWriting.fileDescriptor
                let flags = fcntl(target,F_GETFL)
                guard flags >= 0, fcntl(target,F_SETFL,flags | O_NONBLOCK) == 0,
                      fcntl(target,F_SETNOSIGPIPE,1) == 0 else { throw NativeCommandError("Could not prepare local command input.") }
                let bytes = Data(input.utf8)
                var offset = 0
                while offset < bytes.count {
                    let count = bytes.withUnsafeBytes { pointer in write(target,pointer.baseAddress!.advanced(by:offset),bytes.count-offset) }
                    if count > 0 { offset += count }
                    else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { throw NativeCommandError("Could not write local command input.") }
                    guard DispatchTime.now().uptimeNanoseconds < deadline else { throw NativeCommandError("Local network command timed out.") }
                    if count <= 0 { Thread.sleep(forTimeInterval:0.01) }
                }
                try writer.fileHandleForWriting.close()
            }
            var output = Data(), buffer = [UInt8](repeating:0,count:8192), ended = false
            while true {
                let count = read(fd,&buffer,buffer.count)
                if count > 0 {
                    guard output.count + count <= outputLimit else { throw NativeCommandError("Local command output limit exceeded.") }
                    output.append(contentsOf:buffer.prefix(count))
                } else if count == 0 { ended = true }
                else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    throw NativeCommandError("Could not read local command output.")
                }
                if !process.isRunning && ended { return (process.terminationStatus,String(decoding:output,as:UTF8.self)) }
                guard DispatchTime.now().uptimeNanoseconds < deadline else { throw NativeCommandError("Local network command timed out.") }
                if count <= 0 { Thread.sleep(forTimeInterval:0.01) }
            }
        } catch { stop(); throw error }
    }
}
