// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import Combine

@MainActor private final class PanelHost: NSHostingController<Panel> {
    var dismissPanel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismissPanel?() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = PFConnection()
    private lazy var model = Model(engine: engine)
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var iconUpdates: AnyCancellable?
    private var finishing = false
    private var approved = false
    private var pendingSystemReply = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--verify-network"] || arguments == ["--verify-encrypted-dns"] {
            Task { let code = await NetworkVerification.run(encryptedDNS: arguments == ["--verify-encrypted-dns"]); exit(code) }
            return
        }
        if Bundle.main.bundleURL.path != "/Applications/MoleDPI.app" {
            let alert = NSAlert()
            alert.messageText = "Move MoleDPI to Applications"
            alert.informativeText = "Drag MoleDPI onto Applications in the disk image, then open it from Applications."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let binaries = ["tpws", "moledpi-service", "moledpi-pf"]
        guard let resources = Bundle.main.resourceURL, binaries.allSatisfy({
            FileManager.default.isExecutableFile(atPath: resources.appendingPathComponent($0).path)
        }) else {
            let alert = NSAlert()
            alert.messageText = "MoleDPI is incomplete"
            alert.informativeText = "Copy a fresh copy from the disk image to Applications."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = status
        if let button = status.button {
            iconUpdates = Publishers.CombineLatest(model.$state, model.$recovering).sink { [weak button] state, recovering in
                button?.image = MenuIcon.make(recovering ? .digging : state)
            }
            button.setAccessibilityLabel("MoleDPI")
            button.target = self
            button.action = #selector(statusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.animates = false
        popover.behavior = .transient
        let host = PanelHost(rootView: Panel(model: model))
        host.dismissPanel = { [weak self] in self?.hidePanel() }
        popover.contentViewController = host
        popover.contentSize = NSSize(width: PanelMetrics.width, height: PanelMetrics.height)
        menu.addItem(withTitle: "Quit MoleDPI", action: #selector(quitFromMenu), keyEquivalent: "").target = self
        if arguments.count == 2, arguments[0] == "--verify-quit" {
            Task { await verifyQuit(arguments[1]) }
        }
    }
    func applicationDidResignActive(_ notification: Notification) { hidePanel() }
    private func hidePanel() {
        popover.close()
    }
    private func showPanel() {
        guard let button = item?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    @objc private func statusClick(_ button: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else if popover.isShown {
            hidePanel()
        } else {
            showPanel()
        }
    }
    @objc private func quitFromMenu() { beginShutdown() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if approved { return .terminateNow }
        pendingSystemReply = true
        beginShutdown()
        return .terminateLater
    }
    private func beginShutdown() {
        guard !finishing else { return }
        finishing = true
        model.beginShutdown()
        Task {
            do {
                try await model.waitForShutdown()
                approved = true
                popover.performClose(nil)
                if pendingSystemReply { NSApp.reply(toApplicationShouldTerminate: true) }
                else { NSApp.terminate(nil) }
            } catch {
                finishing = false
                if pendingSystemReply {
                    pendingSystemReply = false
                    NSApp.reply(toApplicationShouldTerminate: false)
                }
                model.quitError = FriendlyError.message(error)
                model.showDetails = false
                showPanel()
            }
        }
    }

    // Opt-in integration check: exercise the exact target of the native menu item.
    private func verifyQuit(_ scenario: String) async {
        switch scenario {
        case "idle": break
        case "immediate": model.connect()
        case "connecting":
            model.connect()
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard model.state == .digging else { exit(71) }
        case "starting-worker":
            model.connect()
            let until = DispatchTime.now() + .seconds(15)
            while await engine.sessionStatusForTesting() == nil && DispatchTime.now() < until {
                try? await Task.sleep(nanoseconds: 3_000_000)
            }
            guard model.state == .digging, await engine.sessionStatusForTesting() != nil else { exit(73) }
        case "disconnecting":
            model.connect(); await model.task?.value
            guard model.state == .on else { exit(74) }
            model.disconnect()
        case "panel":
            model.connect(); await model.task?.value
            guard model.state == .on, let session = await engine.sessionStatusForTesting() else { exit(75) }
            showPanel()
            guard popover.isShown else { exit(76) }
            popover.contentViewController?.cancelOperation(nil)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !popover.isShown else { exit(77) }
            showPanel()
            guard popover.isShown, model.state == .on, await engine.sessionStatusForTesting() == session,
                  await engine.health(targets: model.sites)?.allSatisfy({ $0.reachable == true }) == true else { exit(78) }
        case "connected", "engine-failure":
            model.connect(); await model.task?.value
            let expected: Model.State = scenario == "connected" ? .on : .off
            guard model.state == expected else { fputs("Unexpected state: " + model.detail + "\n", stderr); exit(72) }
        default: exit(64)
        }
        print("QUIT TEST: " + scenario + " → " + menu.item(at: 0)!.title); fflush(stdout)
        menu.performActionForItem(at: 0)
        // Both requests arrive before the shutdown Task gets its first time slice.
        model.connect()
        menu.performActionForItem(at: 0)
    }
}
@main struct MoleDPIApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
