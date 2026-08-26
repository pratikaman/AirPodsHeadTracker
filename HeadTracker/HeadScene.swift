import SceneKit
import simd
import AppKit

/// Builds the 3D head out of SceneKit primitives and applies orientation updates.
final class HeadScene {

    let scene = SCNScene()
    private let headNode = SCNNode()

    init() {
        scene.background.contents = NSColor.clear

        // Camera in front of the face (+Z side).
        let camera = SCNCamera()
        camera.fieldOfView = 40
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4.2)
        scene.rootNode.addChildNode(cameraNode)

        // Lights.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 400
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 800
        key.eulerAngles = SCNVector3(-0.4, 0.4, 0)
        scene.rootNode.addChildNode(key)

        buildHead()
        scene.rootNode.addChildNode(headNode)
    }

    /// `q` is the baseline-relative orientation from MotionManager.
    /// `mirrored` shows the head the way a mirror would (more intuitive to control).
    func update(_ q: simd_quatf, mirrored: Bool) {
        let display = mirrored
            ? simd_quatf(ix: q.imag.x, iy: -q.imag.y, iz: -q.imag.z, r: q.real)
            : q
        headNode.simdOrientation = display
    }

    // MARK: - Model

    private func buildHead() {
        let skin = material(NSColor(calibratedRed: 0.82, green: 0.65, blue: 0.55, alpha: 1))
        let dark = material(NSColor(calibratedWhite: 0.15, alpha: 1))
        let podWhite = material(NSColor(calibratedWhite: 0.95, alpha: 1))

        // Skull: a slightly flattened sphere.
        let skull = SCNNode(geometry: SCNSphere(radius: 0.8))
        skull.geometry!.materials = [skin]
        skull.scale = SCNVector3(0.85, 1.0, 0.9)
        headNode.addChildNode(skull)

        // Nose: cone pointing out of the face (+Z).
        let noseGeo = SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.32)
        noseGeo.materials = [skin]
        let nose = SCNNode(geometry: noseGeo)
        nose.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        nose.position = SCNVector3(0, -0.05, 0.72)
        headNode.addChildNode(nose)

        // Eyes.
        for x: CGFloat in [-0.26, 0.26] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.075))
            eye.geometry!.materials = [dark]
            eye.position = SCNVector3(x, 0.18, 0.62)
            headNode.addChildNode(eye)
        }

        // Ears with little AirPods stems.
        for x: CGFloat in [-0.68, 0.68] {
            let ear = SCNNode(geometry: SCNSphere(radius: 0.16))
            ear.geometry!.materials = [skin]
            ear.scale = SCNVector3(0.45, 1, 1)
            ear.position = SCNVector3(x, 0, 0)
            headNode.addChildNode(ear)

            let bud = SCNNode(geometry: SCNCapsule(capRadius: 0.045, height: 0.28))
            bud.geometry!.materials = [podWhite]
            bud.position = SCNVector3(x + (x < 0 ? -0.06 : 0.06), -0.18, 0.06)
            bud.eulerAngles = SCNVector3(0.25, 0, x < 0 ? -0.15 : 0.15)
            headNode.addChildNode(bud)
        }

        // Cap visor so roll/yaw are easy to read.
        let visorGeo = SCNCylinder(radius: 0.45, height: 0.06)
        visorGeo.materials = [material(NSColor.systemBlue)]
        let visor = SCNNode(geometry: visorGeo)
        visor.scale = SCNVector3(1, 1, 1.4)
        visor.position = SCNVector3(0, 0.62, 0.45)
        visor.eulerAngles = SCNVector3(-0.25, 0, 0)
        headNode.addChildNode(visor)

        let capGeo = SCNSphere(radius: 0.82)
        capGeo.materials = [material(NSColor.systemBlue)]
        let cap = SCNNode(geometry: capGeo)
        cap.scale = SCNVector3(0.87, 0.55, 0.92)
        cap.position = SCNVector3(0, 0.5, -0.02)
        headNode.addChildNode(cap)
    }

    private func material(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.roughness.contents = 0.7
        return m
    }
}
