import Foundation
import Combine
import UserNotifications
import AppKit

/// Watches gravity-referenced neck tilt, accumulates daily upright/slouch time,
/// and nudges with a notification after sustained slouching.
///
/// Down-tilt comes from the gravity vector, so it is absolute and immune to the
/// yaw drift that affects the 3D view — the right signal for posture.
final class PostureMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    // MARK: Settings (persisted)

    @Published var nudgesEnabled: Bool {
        didSet {
            defaults.set(nudgesEnabled, forKey: "posture.nudgesEnabled")
            if nudgesEnabled { requestNotificationAuth() }
        }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "posture.soundEnabled") }
    }
    /// System sound used for sound nudges. Changing it plays a preview.
    @Published var soundName: String {
        didSet {
            defaults.set(soundName, forKey: "posture.soundName")
            NSSound(named: soundName)?.play()
        }
    }
    /// Degrees of down-tilt beyond the calibrated neutral that counts as slouching.
    @Published var thresholdDegrees: Double {
        didSet { defaults.set(thresholdDegrees, forKey: "posture.threshold") }
    }
    /// Sustained slouch duration before the first nudge (and between repeat nudges).
    @Published var nudgeAfterSeconds: Double {
        didSet { defaults.set(nudgeAfterSeconds, forKey: "posture.nudgeAfter") }
    }
    /// Raw down-tilt captured while sitting tall. nil until first calibration.
    @Published private(set) var referenceDegrees: Double?

    // MARK: Live state

    @Published private(set) var rawDownDegrees: Double = 0
    /// Down-tilt relative to the calibrated neutral. Positive = looking down.
    @Published private(set) var tiltDegrees: Double = 0
    @Published private(set) var isSlouching = false
    @Published private(set) var slouchStartedAt: Date?

    // MARK: Today's stats

    @Published private(set) var uprightSeconds: Double = 0
    @Published private(set) var slouchSeconds: Double = 0
    @Published private(set) var nudgeCount: Int = 0

    struct DayStat: Identifiable {
        let id: String
        let date: Date
        let upright: Double
        let slouched: Double
        let nudges: Int
        var slouchFraction: Double {
            let total = upright + slouched
            return total > 0 ? slouched / total : 0
        }
    }

    // MARK: Internals

    private let defaults = UserDefaults.standard
    private var lastSampleAt: Date?
    private var lastNudgeAt: Date?
    private var lastFlushAt = Date.distantPast
    private var dayKey: String

    /// Exit hysteresis so the state doesn't flap right at the threshold.
    private let exitMargin = 3.0

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    override init() {
        nudgesEnabled = defaults.object(forKey: "posture.nudgesEnabled") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "posture.soundEnabled") as? Bool ?? true
        soundName = defaults.string(forKey: "posture.soundName") ?? "Glass"
        thresholdDegrees = defaults.object(forKey: "posture.threshold") as? Double ?? 15
        nudgeAfterSeconds = defaults.object(forKey: "posture.nudgeAfter") as? Double ?? 60
        referenceDegrees = defaults.object(forKey: "posture.reference") as? Double
        dayKey = Self.dayFormatter.string(from: Date())
        super.init()
        loadToday()
        UNUserNotificationCenter.current().delegate = self
        if nudgesEnabled { requestNotificationAuth() }
    }

    // MARK: Sample intake (called at ~25 Hz from MotionManager)

    func update(rawDownDegrees raw: Double, at now: Date) {
        rawDownDegrees = raw
        tiltDegrees = raw - (referenceDegrees ?? 0)

        rolloverIfNeeded(now)

        if isSlouching {
            if tiltDegrees < thresholdDegrees - exitMargin {
                isSlouching = false
                slouchStartedAt = nil
            }
        } else if tiltDegrees > thresholdDegrees {
            isSlouching = true
            slouchStartedAt = now
        }

        // Accumulate time. dt is clamped so gaps (buds out, app asleep) don't count.
        if let last = lastSampleAt {
            let dt = min(now.timeIntervalSince(last), 1.0)
            if dt > 0 {
                if isSlouching { slouchSeconds += dt } else { uprightSeconds += dt }
            }
        }
        lastSampleAt = now

        if nudgesEnabled || soundEnabled, isSlouching,
           let start = slouchStartedAt,
           now.timeIntervalSince(start) >= nudgeAfterSeconds,
           now.timeIntervalSince(lastNudgeAt ?? .distantPast) >= nudgeAfterSeconds {
            lastNudgeAt = now
            sendNudge(after: now.timeIntervalSince(start))
        }

        if now.timeIntervalSince(lastFlushAt) > 15 {
            lastFlushAt = now
            flush()
        }
    }

    /// Captures the current pose as "sitting tall".
    func calibrate() {
        referenceDegrees = rawDownDegrees
        defaults.set(rawDownDegrees, forKey: "posture.reference")
        isSlouching = false
        slouchStartedAt = nil
    }

    // MARK: History

    func lastDays(_ n: Int) -> [DayStat] {
        let dict = defaults.dictionary(forKey: "posture.days") as? [String: [Double]] ?? [:]
        var out: [DayStat] = []
        for i in 0..<n {
            guard let date = Calendar.current.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let key = Self.dayFormatter.string(from: date)
            if key == dayKey {
                out.append(DayStat(id: key, date: date, upright: uprightSeconds,
                                   slouched: slouchSeconds, nudges: nudgeCount))
            } else if let a = dict[key], a.count >= 3 {
                out.append(DayStat(id: key, date: date, upright: a[0],
                                   slouched: a[1], nudges: Int(a[2])))
            }
        }
        return out
    }

    static func timeString(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 {
            let m = s / 60, r = s % 60
            return r == 0 ? "\(m)m" : "\(m)m \(r)s"
        }
        let h = s / 3600, m = (s % 3600) / 60
        return "\(h)h \(m)m"
    }

    // MARK: Persistence

    private func loadToday() {
        let dict = defaults.dictionary(forKey: "posture.days") as? [String: [Double]] ?? [:]
        if let a = dict[dayKey], a.count >= 3 {
            uprightSeconds = a[0]
            slouchSeconds = a[1]
            nudgeCount = Int(a[2])
        }
    }

    private func rolloverIfNeeded(_ now: Date) {
        let key = Self.dayFormatter.string(from: now)
        guard key != dayKey else { return }
        flush()
        dayKey = key
        uprightSeconds = 0
        slouchSeconds = 0
        nudgeCount = 0
    }

    private func flush() {
        var dict = defaults.dictionary(forKey: "posture.days") as? [String: [Double]] ?? [:]
        dict[dayKey] = [uprightSeconds, slouchSeconds, Double(nudgeCount)]
        if dict.count > 20, let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) {
            dict = dict.filter { key, _ in
                guard let d = Self.dayFormatter.date(from: key) else { return false }
                return d >= cutoff
            }
        }
        defaults.set(dict, forKey: "posture.days")
    }

    // MARK: Notifications

    private func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Names in /System/Library/Sounds — the classic macOS alert sounds.
    static let systemSounds = [
        "Glass", "Ping", "Tink", "Pop", "Purr", "Blow", "Bottle",
        "Frog", "Funk", "Hero", "Morse", "Submarine", "Sosumi", "Basso",
    ]

    private func sendNudge(after seconds: TimeInterval) {
        nudgeCount += 1
        flush()
        if soundEnabled {
            NSSound(named: soundName)?.play()
        }
        guard nudgesEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Posture check"
        content.body = "You've been looking down for \(Self.timeString(seconds)). "
            + "Straighten up and relax your shoulders."
        content.sound = soundEnabled ? nil : .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Show nudges even when HeadTracker is the frontmost app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
