// SPDX-License-Identifier: GPL-3.0-only
// Offscreen UI fixtures only. This executable never connects a network engine.
import SwiftUI
import AppKit
@main struct Render {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let output = CommandLine.arguments.dropFirst().first ?? "."
        let icon = MenuIcon.make()
        let iconRep = NSBitmapImageRep(data: icon.tiffRepresentation!)!
        try! iconRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/MoleDPI-menu-icon.png"))
        for (name,state) in [("off",Model.State.off),("digging",.digging),("connected",.on),("failed",.off),("about",.off),("help",.off)] {
            let model = Model()
            model.showDetails = name == "about" || name == "help"
            model.state = state
            model.detail = state == .on ? "The mole is underground. Tunnel ready!" : state == .digging ? "The mole is digging underground." : "The mole is still above ground."
            if name == "failed" { model.detail = "Connection failed — UI preview only." }
            if name == "help" { model.reviewConnectionHelp() }
            let host = NSHostingView(rootView: Panel(model: model))
            host.frame = NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.height)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/MoleDPI-\(name).png"))
            window.contentView = nil
        }
    }
}
