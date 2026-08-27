import CoreMotion
import simd
import Foundation
import Combine

/// Wraps CMHeadphoneMotionManager and publishes head orientation relative to a
/// user-settable baseline ("recenter").
final class MotionManager: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {

    enum Status: Equatable {
        case idle           // not started yet
        case unavailable    // no headphone motion support on this system
        case denied         // motion permission denied
        case waiting        // started, waiting for AirPods to stream
        case streaming      // receiving samples
    }

    @Published private(set) var status: Status = .idle
    /// Orientation relative to the baseline, in the headphone frame.
    @Published private(set) var quaternion = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    /// Degrees, derived from `quaternion`. Positive pitch = looking up.
    @Published private(set) var pitch: Double = 0
    @Published private(set) var yaw: Double = 0
    @Published private(set) var roll: Double = 0
    @Published private(set) var sampleRate: Double = 0
    @Published private(set) var lastSample: Date?
    @Published private(set) var authDescription: String = ""
    @Published private(set) var lastError: String?

    /// Posture tracking, fed from the same sample stream.
    let posture = PostureMonitor()

    private let manager = CMHeadphoneMotionManager()
    private var baseline: simd_quatf?
    private var rateWindow: [Date] = []
    private var started = false
    private var postureForward: AnyCancellable?

    override init() {
        super.init()
        manager.delegate = self
        // Re-publish nested changes so views observing MotionManager (and the
        // menu bar label) update when posture state changes.
        postureForward = posture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start() {
        if started { return }
        started = true
        refreshAuth()
        guard manager.isDeviceMotionAvailable else {
            status = .unavailable
            return
        }
        if CMHeadphoneMotionManager.authorizationStatus() == .denied {
            status = .denied
            return
        }
        status = .waiting
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            self.refreshAuth()
            if let error = error as NSError? {
                self.lastError = "\(error.domain) \(error.code): \(error.localizedDescription)"
                // CMErrorMotionActivityNotAuthorized == 105
                if CMHeadphoneMotionManager.authorizationStatus() == .denied
                    || (error.domain == CMErrorDomain && error.code == 105) {
                    self.status = .denied
                }
                return
            }
            guard let motion else { return }
            self.lastError = nil
            self.handle(motion)
        }
    }

    private func refreshAuth() {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .notDetermined: authDescription = "not determined (no prompt answered yet)"
        case .restricted: authDescription = "restricted"
        case .denied: authDescription = "denied"
        case .authorized: authDescription = "authorized"
        @unknown default: authDescription = "unknown"
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        started = false
        status = .idle
        baseline = nil
        rateWindow.removeAll()
    }

    /// Makes the current head pose the new zero.
    func recenter() {
        baseline = nil
    }

    // MARK: - CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            if self.status == .idle || self.status == .waiting { self.status = .waiting }
            self.baseline = nil
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            if self.status == .streaming { self.status = .waiting }
            self.baseline = nil
            self.sampleRate = 0
        }
    }

    // MARK: - Sample handling

    private func handle(_ motion: CMDeviceMotion) {
        let raw = simd_quatf(
            ix: Float(motion.attitude.quaternion.x),
            iy: Float(motion.attitude.quaternion.y),
            iz: Float(motion.attitude.quaternion.z),
            r: Float(motion.attitude.quaternion.w)
        ).normalized

        if baseline == nil { baseline = raw }
        let q = baseline!.inverse * raw

        status = .streaming
        quaternion = q

        // Headphone frame (assumed): X through right ear, Y up, Z out of the face.
        // Derive display angles from where the face points. If a sign feels
        // backwards on-device, flip it here — it's purely cosmetic.
        let forward = q.act(SIMD3<Float>(0, 0, 1))
        let right = q.act(SIMD3<Float>(1, 0, 0))

        let rad2deg = 180.0 / Double.pi
        yaw = atan2(Double(forward.x), Double(forward.z)) * rad2deg
        pitch = asin(Double(max(-1, min(1, forward.y)))) * rad2deg
        roll = atan2(Double(right.y), Double(right.x)) * rad2deg

        // Rolling sample-rate estimate over the last second.
        let now = Date()
        lastSample = now
        rateWindow.append(now)
        rateWindow.removeAll { now.timeIntervalSince($0) > 1.0 }
        sampleRate = Double(rateWindow.count)

        // Posture: gravity-referenced down-tilt. Gravity is absolute, so this
        // ignores the recenter baseline and is immune to yaw drift.
        // Head frame: +Z out of the face; looking down tips gravity toward +Z.
        let g = motion.gravity
        posture.update(
            rawDownDegrees: asin(max(-1.0, min(1.0, g.z))) * rad2deg,
            at: now
        )
    }
}
