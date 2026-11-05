// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
struct UpdateControls: View {
    @ObservedObject var checker: UpdateChecker
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Button("Check for Updates") { checker.check() }.disabled(checker.checking).buttonStyle(.plain)
            if !checker.message.isEmpty {
                Text(checker.message).font(.system(size:12)).foregroundStyle(MolePalette.secondary)
            }
            if let url = checker.releaseURL {
                Button("View Release") { NSWorkspace.shared.open(url) }.buttonStyle(.plain)
            }
        }
    }
}
