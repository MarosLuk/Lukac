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
            case "applyShield":
                bridge.applyShield()
                result(nil)
            case "clearShield":
                bridge.clearShield()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
