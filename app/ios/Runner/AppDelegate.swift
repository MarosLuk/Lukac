import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }

        let channel = FlutterMethodChannel(
            name: "com.lukac.timerewards/enforcement",
            binaryMessenger: controller.binaryMessenger
        )

        let bridge = FamilyControlsBridge(presenter: controller)

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "hasPermissions":
                result(bridge.hasAuthorization())
            case "requestPermissions":
                bridge.requestAuthorization { ok in
                    result(ok)
                }
            case "listInstalledApps":
                // iOS does not expose the installed-app list. The user picks
                // apps via the Family Activity Picker instead.
                result([])
            case "pickApps":
                bridge.presentPicker { ok in
                    result(ok)
                }
            case "pickAllowedApps":
                bridge.presentAllowedPicker { ok in
                    result(ok)
                }
            case "listEssentialApps":
                // iOS has no equivalent concept — FamilyControls already
                // keeps system apps out of the shielded selection.
                result([])
            case "applyShield":
                // The call may include `packages` and `allowed` lists in
                // its args. iOS ignores both because the native layer
                // holds the authoritative FamilyActivitySelection objects
                // (`selection` and `allowedSelection`). The bridge's
                // applyShield() computes the effective shield from those.
                bridge.applyShield()
                result(nil)
            case "clearShield":
                bridge.clearShield()
                result(nil)
            case "setAllowList":
                // iOS holds the allow-list as a FamilyActivitySelection
                // internally, populated by `pickAllowedApps`. There is
                // nothing to do here with a string list of packages, but
                // we accept the call so the Flutter layer stays platform
                // agnostic.
                result(nil)
            case "hasNotificationAccess":
                // Public APIs can't intercept per-app notifications on iOS.
                // The equivalent best-effort is a Focus mode, which we can
                // only suggest — not query — so always report false.
                result(false)
            case "requestNotificationAccess":
                // Best-effort: deep-link to the app's Settings page so the
                // user can configure a Focus that hides shielded apps.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
