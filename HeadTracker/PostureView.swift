import SwiftUI
import AppKit

/// Menu bar popover: live tilt gauge, today's stats, 7-day history, settings.
struct PostureView: View {
    @ObservedObject var motion: MotionManager
    @ObservedObject var posture: PostureMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            gauge
            Divider()
            today
            history
            Divider()
            controls
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { motion.start() }
    }

    // MARK: Header

    private var streaming: Bool { motion.status == .streaming }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(streaming ? (posture.isSlouching ? .red : .green) : .gray)
                .frame(width: 9, height: 9)
            Text(headerText)
                .font(.callout)
                .lineLimit(1)
            Spacer()
        }
    }

    private var headerText: String {
        guard streaming else { return "Waiting for AirPods motion…" }
        let deg = Int(posture.tiltDegrees.rounded())
        if posture.isSlouching, let start = posture.slouchStartedAt {
            let dur = PostureMonitor.timeString(Date().timeIntervalSince(start))
            return "Slouching — \(deg)° down for \(dur)"
        }
        return "Upright — \(deg)° down"
    }

    // MARK: Gauge

    private var gauge: some View {
        VStack(alignment: .leading, spacing: 4) {
            Gauge(value: min(max(posture.tiltDegrees, -10), 40), in: -10...40) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(posture.tiltDegrees.rounded()))°")
            }
            .gaugeStyle(.accessoryLinear)
            .tint(Gradient(colors: [.green, .green, .yellow, .red]))
            Text("Neck tilt · nudge threshold \(Int(posture.thresholdDegrees))°")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Stats

    private var today: some View {
        HStack(spacing: 20) {
            stat("Upright", PostureMonitor.timeString(posture.uprightSeconds))
            stat("Slouched", slouchedText)
            stat("Nudges", "\(posture.nudgeCount)")
        }
        .frame(maxWidth: .infinity)
    }

    private var slouchedText: String {
        let total = posture.uprightSeconds + posture.slouchSeconds
        let pct = total > 0 ? Int((posture.slouchSeconds / total * 100).rounded()) : 0
        return "\(PostureMonitor.timeString(posture.slouchSeconds)) (\(pct)%)"
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced))
        }
    }

    @ViewBuilder
    private var history: some View {
        let days = posture.lastDays(7)
        if days.count > 1 {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(days) { day in
                    HStack(spacing: 8) {
                        Text(day.date, format: .dateTime.weekday(.abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        ProgressView(value: day.slouchFraction)
                            .tint(.orange)
                        Text("\(Int((day.slouchFraction * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Text("Share of tracked time spent slouched")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                posture.calibrate()
            } label: {
                Label("Set Upright Posture", systemImage: "scope")
            }
            .disabled(!streaming)
            Text(posture.referenceDegrees == nil
                 ? "Sit tall, look at your screen, then click."
                 : "Recalibrate whenever your setup changes.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Text("Nudge past").font(.caption)
                Slider(value: $posture.thresholdDegrees, in: 5...35, step: 1)
                Text("\(Int(posture.thresholdDegrees))°")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
            HStack {
                Text("after").font(.caption)
                Slider(value: $posture.nudgeAfterSeconds, in: 15...600, step: 15)
                Text(PostureMonitor.timeString(posture.nudgeAfterSeconds))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            Toggle("Notification nudges", isOn: $posture.nudgesEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
            HStack {
                Toggle("Sound nudges", isOn: $posture.soundEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Picker("", selection: $posture.soundName) {
                    ForEach(PostureMonitor.systemSounds, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 110)
                .disabled(!posture.soundEnabled)
            }
            HStack {
                Toggle("Spoken nudges", isOn: $posture.speechEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button {
                    posture.speakNudge()
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Preview")
                .disabled(!posture.speechEnabled)
            }
            TextField("What should it say?", text: $posture.speechText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .disabled(!posture.speechEnabled)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Open Tracker Window") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}
