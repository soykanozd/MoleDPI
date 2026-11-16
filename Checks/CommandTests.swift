// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

@main struct CommandTests {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--resist" {
            signal(SIGTERM,SIG_IGN)
            try Data(String(getpid()).utf8).write(to:URL(fileURLWithPath:args[2]))
            while true { try await Task.sleep(nanoseconds:1_000_000_000) }
        }
        if args.count == 2 && args[1] == "--flood" {
            FileHandle.standardOutput.write(Data(repeating:65,count:500000)); return
        }
        if args.count == 2 && args[1] == "--echo" {
            FileHandle.standardOutput.write(FileHandle.standardInput.readDataToEndOfFile()); return
        }
        func expect(_ condition: Bool,_ message: String) throws {
            guard condition else { throw NativeCommandError(message) }; print("PASS " + message)
        }
        let binary = URL(fileURLWithPath:args[0]).standardized.path
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let echo = try BoundedCommand.run(binary,["--echo"],input:"bounded input")
        try expect(echo.0 == 0 && echo.1 == "bounded input","command stdin/stdout roundtrip")
        let pidFile = directory.appendingPathComponent("timeout-ready")
        let begin = DispatchTime.now().uptimeNanoseconds
        do { _ = try BoundedCommand.run(binary,["--resist",pidFile.path],timeout:0.3); throw NativeCommandError("Timeout was ignored") }
        catch let error as NativeCommandError { try expect(error.localizedDescription.contains("timed out"),"uncooperative command times out") }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds-begin)/1_000_000_000
        try expect(elapsed < 3,"command termination is bounded")
        let timedPID = Int32(String(decoding:try Data(contentsOf:pidFile),as:UTF8.self))!
        try expect(kill(timedPID,0) == -1 && errno == ESRCH,"timed-out child was reaped")
        do { _ = try BoundedCommand.run(binary,["--flood"],outputLimit:32768); throw NativeCommandError("Output limit was ignored") }
        catch let error as NativeCommandError { try expect(error.localizedDescription.contains("output limit"),"command output is capped") }
        let ready = directory.appendingPathComponent("cancel-ready")
        let process = Process(); process.executableURL = URL(fileURLWithPath:binary)
        process.arguments = ["--resist",ready.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        let task = Task { try await OwnedCommand(process).run() }
        for _ in 0..<1000 {
            if FileManager.default.fileExists(atPath:ready.path) { break }
            try await Task.sleep(nanoseconds:2_000_000)
        }
        try expect(FileManager.default.fileExists(atPath:ready.path),"cancellation fixture is ready")
        try expect(BoundedCommand.stop(pid:process.processIdentifier,executable:"/unrelated/fixture"),"mismatched executable is left alone")
        try expect(process.isRunning,"identity mismatch does not signal the process")
        let cancelledAt = DispatchTime.now().uptimeNanoseconds
        task.cancel(); _ = try? await task.value
        try expect(!process.isRunning && Double(DispatchTime.now().uptimeNanoseconds-cancelledAt)/1_000_000_000 < 4,
                   "cancelled owned child cannot hang shutdown")
    }
}
