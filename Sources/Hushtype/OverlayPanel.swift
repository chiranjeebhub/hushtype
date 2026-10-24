import AppKit
import SwiftUI

/// The floating "listening" pill near the bottom of the screen. It never takes focus,
/// so the app you're dictating into stays active.
@MainActor
final class OverlayPanel {
    private let panel: NSPanel

    init(controller: DictationController) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 44),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OverlayView(controller: controller))
    }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 48))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct OverlayView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        HStack(spacing: 10) {
            switch controller.phase {
            case .recording:
                Circle().fill(controller.isCommand ? .purple : .red).frame(width: 8, height: 8)
                if controller.isCommand {
                    Label("Command", systemImage: "wand.and.stars").labelStyle(.titleAndIcon)
                }
                LevelBars(level: controller.level)
                if controller.isHandsFree {
                    Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.8))
                    Text("Tap to finish · Esc to cancel").foregroundStyle(.white.opacity(0.8))
                }
            case .transcribing, .cleaning:
                ProgressView().controlSize(.small)
                Text(controller.isCommand ? "Working on it…"
                     : controller.phase == .transcribing ? "Transcribing…" : "Polishing…")
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message).lineLimit(1)
            case .notice(let message):
                Image(systemName: "info.circle.fill").foregroundStyle(.white.opacity(0.8))
                Text(message).lineLimit(1)
            case .idle:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small live waveform driven by the current input level.
private struct LevelBars: View {
    let level: Float
    private let weights: [Float] = [0.45, 0.7, 1.0, 0.8, 0.55, 0.9, 0.6, 0.4]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: CGFloat(4 + 18 * min(1, level * weights[index] * 1.4)))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
