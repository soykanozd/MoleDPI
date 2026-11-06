// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@main struct Uninstall {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove MoleDPI"
        alert.informativeText = "Disconnect and quit MoleDPI first. This removes its installed helper. Your existing network settings and personal files are preserved. macOS will ask for administrator approval."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let script = """
        set -eu
        export PATH=/usr/bin:/bin:/usr/sbin:/sbin
        ! pgrep -x MoleDPI >/dev/null || exit 75
        ! pgrep -x moledpi-pf >/dev/null || exit 75
        for d in /Library /Library/LaunchDaemons /Library/PrivilegedHelperTools; do
          [ ! -L "$d" ] || exit 73
        done
        r='/Library/PrivilegedHelperTools/local.moledpi'
        [ ! -L "$r" ] || exit 73
        if [ -e "$r" ]; then [ "$(stat -f '%u:%Lp' "$r")" = '0:755' ] || exit 73; fi
        label=local.moledpi.pf-service
        if launchctl print system/$label >/dev/null 2>&1; then launchctl bootout system/$label; fi
        rm -f /Library/LaunchDaemons/$label.plist
        for n in moledpi-service moledpi-pf tpws ciadpi tunnel-runner moledpi-udp; do rm -f "$r/$n"; done
        if [ -d "$r" ]; then rmdir "$r"; fi
        """
        func quote(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of:"\n",with:"\\n") + "\""
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script " + quote(script) + " with prompt \"Remove the MoleDPI helper.\" with administrator privileges"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw NSError(domain:"MoleDPI",code:1) }
            let result = NSAlert()
            result.messageText = "Helper removed"
            result.informativeText = "You can now move MoleDPI from Applications to the Trash."
            result.runModal()
        } catch {
            let result = NSAlert()
            result.messageText = "Removal could not finish"
            result.informativeText = "Make sure MoleDPI is disconnected and has quit, then try again. Approve the macOS request if you want to remove the helper."
            result.runModal()
        }
    }
}
