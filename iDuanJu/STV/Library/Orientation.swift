import SwiftUI
import UIKit

/// Portrait by default; unlock all orientations while the player is on screen.
final class OrientationGate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait
    private static var rotationGeneration = 0
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.mask }

    @MainActor static func unlock() {
        rotationGeneration += 1
        mask = .allButUpsideDown
        refresh()
    }
    /// 横屏 button: rotate now; rotation stays unlocked so turning the phone back to portrait exits.
    @MainActor static func enterLandscape() {
        rotationGeneration += 1
        mask = .allButUpsideDown
        refresh()
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
    }
    /// 退出横屏 button.
    @MainActor static func exitLandscape() {
        rotationGeneration += 1
        let generation = rotationGeneration
        // UIKit may ignore a portrait geometry request made while the supported mask remains unrestricted.
        // Constrain during the rotation, then restore sensor rotation after the transition completes.
        mask = .portrait
        refresh()
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            // A dismissed player must not unlock a subsequent portrait-only screen.
            if generation == rotationGeneration { mask = .allButUpsideDown; refresh() }
        }
    }
    @MainActor static func lockPortrait() {
        rotationGeneration += 1
        mask = .portrait
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        refresh()
    }
    @MainActor private static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for win in scene.windows {
                win.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}
