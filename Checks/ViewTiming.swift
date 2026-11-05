// Visual-only fixture: replay a short and a long verification interval.
import SwiftUI
import AppKit
@main struct ViewTiming {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = Model()
        let host = NSHostingView(rootView: Panel(model: model))
        host.frame = CGRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.height)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        func render(_ seconds: Double) {
            let until = Date().addingTimeInterval(seconds)
            while Date() < until {
                RunLoop.current.run(until: Date().addingTimeInterval(0.016))
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
            }
        }
        render(0.2)
        for delay in [0.5, 3.0, 7.0] {
            print("Visual fixture: simulated verification after \(delay) s")
            model.state = .digging; render(delay)
            model.state = .on; render(0.4)
            model.state = .emerging; render(0.2)
            model.state = .off; render(0.7)
        }
        window.contentView = nil
    }
}
