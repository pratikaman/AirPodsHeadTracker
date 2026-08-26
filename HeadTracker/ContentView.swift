import SwiftUI
import SceneKit
import Combine
import simd

struct ContentView: View {
    @EnvironmentObject var motion: MotionManager
    @AppStorage("mirrored") private var mirrored = true
    @State private var headScene = HeadScene()

    /// Considered stale if no sample for a second (buds out of ear, switched device...).
    @State private var stale = false
    private let staleTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()

            SceneView(scene: headScene.scene, options: [])
                .frame(minWidth: 420, minHeight: 380)

            Divider()
            readouts
        }
        .onAppear { motion.start() }
        .onReceive(motion.$quaternion) { q in
            headScene.update(q, mirrored: mirrored)
        }
        .onChange(of: mirrored) { _, m in
            headScene.update(motion.quaternion, mirrored: m)
        }
        .onReceive(staleTimer) { now in
            stale = motion.lastSample.map { now.timeIntervalSince($0) > 1.0 } ?? true
        }
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.callout)
            Spacer()
            Toggle("Mirror", isOn: $mirrored)
                .toggleStyle(.switch)
                .controlSize(.small)
            Button("Recenter") { motion.recenter() }
                .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch motion.status {
        case .streaming: return stale ? .yellow : .green
        case .waiting: return .yellow
        case .denied, .unavailable: return .red
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch motion.status {
        case .idle:
            return "Starting…"
        case .unavailable:
            return "Headphone motion is not available on this Mac."
        case .denied:
            return "Motion access denied — enable it in System Settings › Privacy & Security › Motion & Fitness."
        case .waiting:
            return "Waiting for AirPods… (connect them to this Mac and put them in your ears)"
        case .streaming:
            return stale
                ? "Stream paused — are the AirPods still in your ears and connected to this Mac?"
                : String(format: "Streaming at %.0f Hz", motion.sampleRate)
        }
    }

    // MARK: - Numbers

    private var readouts: some View {
        HStack(spacing: 24) {
            angle("Pitch", motion.pitch, up: "up", down: "down")
            angle("Yaw", motion.yaw, up: "right", down: "left")
            angle("Roll", motion.roll, up: "right", down: "left")
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func angle(_ name: String, _ value: Double, up: String, down: String) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%+7.1f°", value))
                .font(.system(.title3, design: .monospaced))
            Text(abs(value) < 0.5 ? " " : (value > 0 ? up : down))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 90)
    }
}
