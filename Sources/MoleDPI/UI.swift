// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

// Paths are traced to the supplied character proportions, not an SF Symbol/emoji.
struct MoleArtwork: View, Animatable {
    var depth: CGFloat = 0
    var digging = false
    var tunnel = false
    var onTunnelFrame: (() -> Void)? = nil
    var time: Double = 0
    var animatableData: CGFloat { get { depth } set { depth = newValue } }
    var body: some View {
        Canvas { c, size in
            c.scaleBy(x: size.width / 450, y: size.height / 250)
            let ink = Color(red: 0.075, green: 0.075, blue: 0.075)
            let earth = Color(red: 0.55, green: 0.36, blue: 0.22)
            func shape(_ path: Path, _ color: Color, stroke: CGFloat = 0) {
                c.fill(path, with: .color(color))
                if stroke > 0 { c.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)) }
            }
            func ellipse(_ rect: CGRect, _ color: Color, stroke: CGFloat = 0) { shape(Path(ellipseIn: rect), color, stroke: stroke) }
            var dirt = Path()
            dirt.move(to: CGPoint(x: 47, y: 211))
            dirt.addCurve(to: CGPoint(x: 66, y: 190), control1: CGPoint(x: 33, y: 198), control2: CGPoint(x: 45, y: 187))
            dirt.addCurve(to: CGPoint(x: 95, y: 172), control1: CGPoint(x: 64, y: 173), control2: CGPoint(x: 83, y: 165))
            dirt.addCurve(to: CGPoint(x: 127, y: 171), control1: CGPoint(x: 103, y: 156), control2: CGPoint(x: 121, y: 159))
            dirt.addCurve(to: CGPoint(x: 315, y: 179), control1: CGPoint(x: 176, y: 183), control2: CGPoint(x: 265, y: 170))
            dirt.addCurve(to: CGPoint(x: 350, y: 192), control1: CGPoint(x: 337, y: 166), control2: CGPoint(x: 352, y: 178))
            dirt.addCurve(to: CGPoint(x: 380, y: 210), control1: CGPoint(x: 376, y: 187), control2: CGPoint(x: 394, y: 210))
            dirt.addCurve(to: CGPoint(x: 292, y: 222), control1: CGPoint(x: 379, y: 235), control2: CGPoint(x: 316, y: 218))
            dirt.addCurve(to: CGPoint(x: 184, y: 226), control1: CGPoint(x: 251, y: 239), control2: CGPoint(x: 217, y: 221))
            dirt.addCurve(to: CGPoint(x: 104, y: 224), control1: CGPoint(x: 154, y: 237), control2: CGPoint(x: 120, y: 229))
            dirt.addCurve(to: CGPoint(x: 47, y: 211), control1: CGPoint(x: 76, y: 230), control2: CGPoint(x: 48, y: 224)); dirt.closeSubpath()
            shape(dirt, earth)
            let fraction = min(1, max(0, depth / 215))
            let opening = fraction * fraction * (3 - 2 * fraction)
            if opening > 0 {
                ellipse(CGRect(x: 221 - 95 * opening, y: 207 - 22 * opening,
                               width: 190 * opening, height: 40 * opening), ink)
            }
            if !tunnel || depth < 217 {
                c.drawLayer { layer in
                    var mask = Path(); mask.addRect(CGRect(x: 0, y: 0, width: 450, height: 217)); layer.clip(to: mask)
                    layer.translateBy(x: digging ? sin(time * 13) * 1.6 : 0, y: depth)
                    func fill(_ path: Path, _ color: Color, _ stroke: CGFloat = 6) {
                        layer.fill(path, with: .color(color)); if stroke > 0 { layer.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)) }
                    }
                    let fur = Color(red: 0.43, green: 0.35, blue: 0.31)
                    let skin = Color(red: 0.91, green: 0.73, blue: 0.59)
                    let yellow = Color(red: 1, green: 0.79, blue: 0.24)
                    var body = Path()
                    body.move(to: CGPoint(x: 122, y: 190)); body.addLine(to: CGPoint(x: 145, y: 93))
                    body.addCurve(to: CGPoint(x: 240, y: 66), control1: CGPoint(x: 169, y: 72), control2: CGPoint(x: 213, y: 58))
                    body.addCurve(to: CGPoint(x: 299, y: 91), control1: CGPoint(x: 268, y: 55), control2: CGPoint(x: 304, y: 60))
                    body.addCurve(to: CGPoint(x: 299, y: 144), control1: CGPoint(x: 317, y: 99), control2: CGPoint(x: 304, y: 124))
                    body.addLine(to: CGPoint(x: 277, y: 199)); body.addLine(to: CGPoint(x: 122, y: 202)); body.closeSubpath()
                    fill(body, fur)
                    var cap = Path()
                    cap.move(to: CGPoint(x: 140, y: 94))
                    cap.addCurve(to: CGPoint(x: 224, y: 23), control1: CGPoint(x: 147, y: 52), control2: CGPoint(x: 178, y: 24))
                    cap.addCurve(to: CGPoint(x: 287, y: 72), control1: CGPoint(x: 256, y: 15), control2: CGPoint(x: 282, y: 43))
                    cap.closeSubpath(); fill(cap, yellow)
                    var band = Path(); band.move(to: CGPoint(x: 213, y: 22)); band.addLine(to: CGPoint(x: 223, y: 62)); layer.stroke(band, with: .color(ink), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    var brim = Path(); brim.move(to: CGPoint(x: 135, y: 124))
                    brim.addCurve(to: CGPoint(x: 138, y: 100), control1: CGPoint(x: 121, y: 121), control2: CGPoint(x: 129, y: 108))
                    brim.addCurve(to: CGPoint(x: 284, y: 62), control1: CGPoint(x: 168, y: 71), control2: CGPoint(x: 244, y: 42))
                    brim.addCurve(to: CGPoint(x: 301, y: 81), control1: CGPoint(x: 302, y: 63), control2: CGPoint(x: 308, y: 76))
                    brim.addCurve(to: CGPoint(x: 135, y: 124), control1: CGPoint(x: 259, y: 60), control2: CGPoint(x: 177, y: 91)); brim.closeSubpath()
                    fill(brim, yellow)
                    fill(Path(ellipseIn: CGRect(x: 221, y: 12, width: 44, height: 44)), .white, 10)
                    var glasses = Path(); glasses.move(to: CGPoint(x: 145, y: 112)); glasses.addLine(to: CGPoint(x: 207, y: 108)); glasses.addLine(to: CGPoint(x: 261, y: 97)); glasses.addLine(to: CGPoint(x: 289, y: 91))
                    layer.stroke(glasses, with: .color(ink), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    fill(Path(ellipseIn: CGRect(x: 258, y: 78, width: 43, height: 43)), Color(white: 0.15), 7)
                    fill(Path(ellipseIn: CGRect(x: 197, y: 89, width: 49, height: 49)), Color(white: 0.17), 7)
                    var glint = Path(); glint.move(to: CGPoint(x: 211, y: 124)); glint.addLine(to: CGPoint(x: 232, y: 97))
                    layer.stroke(glint, with: .color(Color(white: 0.23)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    fill(Path(ellipseIn: CGRect(x: 277, y: 104, width: 43, height: 31)), Color(red: 0.94, green: 0.68, blue: 0.57), 0)
                    var whiskers = Path()
                    for (a,b,d,e) in [(327.0,117.0,350.0,113.0),(327,126,352,130),(325,135,341,146)] {
                        whiskers.move(to: CGPoint(x: a, y: b)); whiskers.addQuadCurve(to: CGPoint(x: d, y: e), control: CGPoint(x: (a+d)/2, y: b-2))
                    }
                    layer.stroke(whiskers, with: .color(Color(white: 0.92)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    func paw(_ x: CGFloat, _ y: CGFloat) {
                        var p = Path(); p.move(to: CGPoint(x: x, y: y + 23))
                        p.addCurve(to: CGPoint(x: x + 51, y: y + 18), control1: CGPoint(x: x - 5, y: y - 20), control2: CGPoint(x: x + 46, y: y - 23))
                        p.addLine(to: CGPoint(x: x + 52, y: y + 30)); p.addQuadCurve(to: CGPoint(x: x + 37, y: y + 22), control: CGPoint(x: x + 50, y: y + 45))
                        p.addQuadCurve(to: CGPoint(x: x + 25, y: y + 31), control: CGPoint(x: x + 34, y: y + 47))
                        p.addLine(to: CGPoint(x: x + 20, y: y + 21)); p.addQuadCurve(to: CGPoint(x: x + 9, y: y + 32), control: CGPoint(x: x + 17, y: y + 48))
                        p.closeSubpath(); fill(p, skin, 6)
                    }
                    paw(137, 181 + (digging ? sin(time * 17) * 8 : 0)); paw(280, 181 + (digging ? -sin(time * 17) * 8 : 0))
                }
            }
            // One continuous pose coordinate: the entire mole clears the lip
            // before the foreleg can enter it, in either direction.
            if depth > 235 {
                c.drawLayer { arm in
                    arm.clip(to: Path(CGRect(x: 140, y: 0, width: 165, height: 211)))
                    arm.translateBy(x: 0, y: max(0, 380 - depth))
                    let outline = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    let wrist = Path(roundedRect: CGRect(x: 202, y: 144, width: 48, height: 91), cornerRadius: 19)
                    arm.fill(wrist, with: .color(Color(red: 0.45, green: 0.31, blue: 0.23)))
                    arm.stroke(wrist, with: .color(ink), style: outline)
                    var paw = Path()
                    func q(_ x: CGFloat,_ y: CGFloat,_ cx: CGFloat,_ cy: CGFloat) {
                        paw.addQuadCurve(to: CGPoint(x:x,y:y), control: CGPoint(x:cx,y:cy))
                    }
                    paw.move(to: CGPoint(x:201,y:168))
                    q(195,109,180,144); q(214,84,202,86); q(217,98,229,80)
                    q(205,119,208,105); q(230,88,211,100); q(241,101,247,83)
                    q(226,116,230,106); q(258,120,246,104); q(260,151,270,133)
                    q(238,172,252,166); q(201,168,217,180); paw.closeSubpath()
                    let opening = min(1, max(0.1, (depth - 300) / 80))
                    paw.addEllipse(in: CGRect(x:231,y:125,width:18,height:18*opening))
                    arm.fill(paw, with: .color(Color(red:1,green:0.64,blue:0.46)), style: FillStyle(eoFill:true))
                    arm.stroke(paw, with: .color(ink), style: outline)
                }
            }
            // Foreground rim hides the character as it descends.
            if depth > 0 && (!tunnel || depth < 217) { c.drawLayer { layer in
                var clip = Path(); clip.addRect(CGRect(x: 0, y: 214, width: 450, height: 40)); layer.clip(to: clip); layer.fill(dirt, with: .color(earth))
            } }
            for (x,y,w) in [(8.0,198.0,26.0),(394,201,18),(426,211,9)] { ellipse(CGRect(x: x, y: y, width: w, height: w * 0.65), earth) }
            if digging {
                for n in 0..<6 {
                    let phase = (time * 1.4 + Double(n) / 6).truncatingRemainder(dividingBy: 1)
                    let side = n.isMultiple(of: 2) ? -1.0 : 1.0
                    ellipse(CGRect(x: 220 + side * (65 + phase * 135), y: 205 - sin(phase * .pi) * 68, width: 8, height: 6), earth)
                }
            }

            if depth > 355 {
                let t = min(1, (depth - 355) / 25)
                var marks = Path()
                for (x,y,dx,dy) in [(255.0,74.0,8.0,-16.0),(270,86,17,-9),(277,99,15,0)] {
                    marks.move(to: CGPoint(x:x,y:y)); marks.addLine(to: CGPoint(x:x+dx*t,y:y+dy*t))
                }
                c.stroke(marks, with: .color(.white.opacity(t)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            if tunnel && depth >= 379 { onTunnelFrame?() }
        }.accessibilityLabel(tunnel ? "Mole paw making an OK gesture" : "Mole wearing a yellow helmet and sunglasses")
    }
}
struct MoleHead: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + r.width*x/80, y: r.minY+r.height*y/50) }
        p.move(to: pt(6,41)); p.addQuadCurve(to: pt(13,33), control: pt(3,36))
        p.addCurve(to: pt(54,13), control1: pt(17,14), control2: pt(28,5))
        p.addQuadCurve(to: pt(66,32), control: pt(65,18))
        p.addQuadCurve(to: pt(74,39), control: pt(76,32))
        p.addQuadCurve(to: pt(6,41), control: pt(44,33)); p.closeSubpath(); return p
    }
}
struct HeadLogo: View {
    var body: some View {
        ZStack {
            MoleHead().stroke(.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            Circle().fill(MolePalette.background).overlay(Circle().stroke(.white, lineWidth: 2))
                .frame(width: 8, height: 8).offset(x: 4, y: -7)

        }.frame(width: 36, height: 25)
    }
}
@MainActor final class MoleMotion: ObservableObject { @Published var depth: CGFloat = 0; var visualClock: ConnectClock? }
struct AnimatedMole: View {
    let state: Model.State
    @StateObject private var motion = MoleMotion()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30, paused: state != .digging)) { timeline in
            MoleArtwork(depth: motion.depth, digging: state == .digging, tunnel: state == .on, onTunnelFrame: ConnectClock.enabled ? {
                if let timer = motion.visualClock {
                    timer.mark("view.first-complete-tunnel-frame")
                    motion.visualClock = nil
                }
            } : nil, time: timeline.date.timeIntervalSinceReferenceDate)
        }
        .onAppear { motion.depth = state == .digging ? 100 : state == .on ? 380 : state == .emerging ? 232 : 0 }
        .onChange(of: state) { state in
            switch state {
            case .digging: motion.visualClock = ConnectClock(); motion.depth = 0; withAnimation(.easeOut(duration: 0.8)) { motion.depth = 148 }
            case .emerging: withAnimation(.easeInOut(duration: 0.35)) { motion.depth = 232 }
            case .off: withAnimation(.easeOut(duration: 0.55)) { motion.depth = 0 }
            case .on:
                // Retarget the in-flight descent from its presentation position.
                // The model has already published the verified connection.
                withAnimation(.easeOut(duration: 0.36)) { motion.depth = 380 }
            }
        }
    }
}
enum PanelMetrics {
    static let width: CGFloat = 330
    static let height: CGFloat = 430
}
enum MolePalette {
    static let background = Color(red: 15/255, green: 43/255, blue: 72/255)
    static let dark = Color(red: 28/255, green: 58/255, blue: 89/255)
    static let blue = Color(red: 47/255, green: 128/255, blue: 237/255)
    static let red = Color(red: 240/255, green: 66/255, blue: 64/255)
    static let green = Color(red: 9/255, green: 189/255, blue: 88/255)
    static let secondary = Color(red: 192/255, green: 208/255, blue: 224/255)
}
struct Panel: View {
    @ObservedObject var model: Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func setAbout(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            model.showDetails = visible
        }
    }

    private var hasError: Bool { model.state == .off && (model.recoveryNeeded || model.detail != "The mole is still above ground.") }
    private var title: String {
        if model.quitError != nil { return "Could Not Quit" }
        if model.recovering { return "Reconnecting..." }
        switch model.state {
        case .off: return hasError ? "Connection Failed" : "Not Connected"
        case .digging: return "Connecting..."
        case .on: return "Connected"
        case .emerging: return "Disconnecting..."
        }
    }
    private var subtitle: String {
        if model.quitError != nil { return "Network cleanup needs attention. Retry to finish." }
        if model.recovering { return model.issueMessage ?? "Restoring your connection..." }
        switch model.state {
        case .off: return hasError ? (model.issueMessage ?? "Connection failed. Please try again.") : "The mole is still above ground."
        case .digging: return "The mole is digging its way..."
        case .on: return "You're now underground."
        case .emerging: return "The mole is returning above ground."
        }
    }
    var body: some View {
        ZStack {
            MolePalette.background
            main
                .opacity(model.showDetails ? 0 : 1)
                .disabled(model.showDetails)
                .accessibilityHidden(model.showDetails)
            if model.showDetails {
                if let report = model.diagnostics { diagnostics(report).transition(.opacity) }
                else { about.transition(.opacity) }
            }
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .contextMenu {
            if hasError {
                Button("Review Diagnostics") {
                    model.showDetails = true
                    model.reviewDiagnostics()
                }
            }
            Button("Quit MoleDPI") { NSApplication.shared.terminate(nil) }
        }
    }
    private func diagnostics(_ report: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.reportTitle).font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { model.diagnostics = nil } label: {
                    Image(systemName: "xmark").frame(width: 26, height: 28)
                }.buttonStyle(.plain).accessibilityLabel("Back to About MoleDPI")
            }.frame(height: 52)
            Text(model.reportTitle == "Connection Help" ? "Guidance based on the last observed connection checks." : "Review before sharing. Nothing is sent automatically.")
                .font(.system(size: 13)).foregroundStyle(MolePalette.secondary)
            ScrollView { Text(report).font(.system(size: model.reportTitle == "Connection Help" ? 14 : 12, design: model.reportTitle == "Connection Help" ? .default : .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            if model.reportTitle == "Diagnostics" { Button("Copy Report") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
            }.padding(.bottom, 14) }
        }.padding(.horizontal, 18).padding(.top, 8)
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("About MoleDPI").font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { setAbout(false) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                        .frame(width: 26, height: 28)
                }.buttonStyle(.plain).accessibilityLabel("Close About MoleDPI")
            }.frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Built for an open internet.").bold()
                    Group {
                        Text("The internet should be a place where people can communicate, explore ideas, and access information without unnecessary restrictions.")
                        Text("MoleDPI was created out of a simple belief: access to information should not depend on where you live or which websites are blocked.")
                        Text("This project is a small contribution to a more open internet. Simple, transparent, and accessible to everyone.")
                    }.foregroundStyle(MolePalette.secondary)
                    Text("The internet should be open to everyone.").bold()
                    Text("Experimental · Bugs and connection failures may occur.").font(.system(size: 12)).foregroundStyle(MolePalette.secondary)
                    UpdateControls(checker: model.updates)
                    Button("Connection Help") { model.reviewConnectionHelp() }.buttonStyle(.plain)
                    Button("Review Diagnostics") { model.reviewDiagnostics() }.buttonStyle(.plain)
                    Text("MoleDPI · Free & Open Source")
                        .font(.system(size: 12)).foregroundStyle(MolePalette.secondary)
                }
                .font(.system(size: 14)).lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 14)
    }

    private var brand: some View {
        HStack(alignment: .center, spacing: 8) {
            HeadLogo().scaleEffect(26/36).frame(width: 26, height: 25)
            Text("MoleDPI").font(.system(size: 18, weight: .semibold))
        }
    }
    private var main: some View {
        VStack(spacing: 0) {
            HStack {
                brand
                Spacer()
                Button { setAbout(true) } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 18))
                        .frame(width: 26, height: 28)
                }.buttonStyle(.plain).accessibilityLabel("About MoleDPI")
            }.frame(height: 52)
            AnimatedMole(state: model.recovering ? .digging : model.state).frame(width: 218, height: 121).padding(.top, 30)
            HStack(spacing: 8) {
                Circle().fill(model.recovering ? .yellow : model.state == .on ? MolePalette.green : model.state == .off ? MolePalette.red : .yellow)
                    .frame(width: 13, height: 13)
                Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(MolePalette.dark, in: Capsule())
            .padding(.top, 16).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(MolePalette.secondary)
                .multilineTextAlignment(.center).lineLimit(2).frame(height: 36).padding(.top, 6)
                .help(model.quitError ?? (hasError ? model.detail : subtitle))
            action.frame(height: 52).padding(.top, 22)
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var action: some View {
        Button {
            if model.quitError != nil { NSApp.terminate(nil) }
            else if model.recovering { model.disconnect() }
            else if model.recoveryNeeded { model.disconnect() }
            else if model.state == .off { model.connect() } else { model.disconnect() }
        } label: {
            Group {
                if model.state == .digging && !model.recovering && model.quitError == nil {
                    ProgressView().controlSize(.small).accessibilityLabel("Cancel connection")
                } else {
                    Text(model.quitError != nil ? "Retry Quit" : model.recovering ? "Disconnect" : model.recoveryNeeded ? "Repair Network" : model.state == .on ? "Disconnect" : model.state == .emerging ? "Disconnecting..." : "Connect")
                }
            }
            .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(model.state == .digging ? MolePalette.dark : model.state == .off && !model.recoveryNeeded ? MolePalette.green : MolePalette.red, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(model.quitError == nil && (model.quitting || model.state == .emerging))
    }
}

enum MenuIcon {
    static func make(_ state: Model.State = .off) -> NSImage {
        let image = NSImage(size: NSSize(width: 25, height: 19), flipped: true) { _ in
            let rect = CGRect(x: 0, y: 0, width: 25, height: 18)
            let path = MoleHead().path(in: rect)
            NSColor.black.setStroke()
            let context = NSGraphicsContext.current!.cgContext
            if state == .on { context.addPath(path.cgPath); context.fillPath() }
            if state == .digging || state == .emerging {
                context.move(to: CGPoint(x:18,y:1)); context.addQuadCurve(to: CGPoint(x:24,y:8), control: CGPoint(x:24,y:2)); context.strokePath()
            }
            context.addPath(path.cgPath); context.setLineWidth(1.5); context.setLineJoin(.round); context.strokePath()
            NSColor.black.setFill()
            let lamp = NSBezierPath(ovalIn: NSRect(x: 13, y: 1, width: 5, height: 5))
            context.saveGState(); context.setBlendMode(.clear); lamp.fill(); context.restoreGState()
            lamp.lineWidth = 1.4; lamp.stroke()
            return true
        }
        image.isTemplate = true; return image
    }
}
