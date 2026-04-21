# Time Rewards (MVP)

A cross-platform app that blocks selected apps on your phone until you complete
tasks. Completing a task earns screen-time minutes that can be "spent" to lift
the shield for a chosen duration.

- **Flutter** handles UI, task ledger, and reward accounting.
- **Android (Kotlin)** enforces via `UsageStatsManager` + an `AccessibilityService` that sends the user HOME when they open a shielded app while the shield is active.
- **iOS (Swift)** enforces via `FamilyControls` + `ManagedSettings`. Requires the `com.apple.developer.family-controls` entitlement from Apple and a real device (iOS 16+).

---

## What is NOT in the MVP (yet)

- Calendar / to-do sync (Google Tasks, Todoist, Apple Reminders). The service
  interface is stubbed at `lib/services/calendar_service.dart`.
- Foreground notification on Android to reduce the chance of the accessibility
  service being killed on aggressive OEM ROMs.
- iOS DeviceActivity extension for scheduled re-shielding when the purchased
  time runs out while the app is backgrounded. The in-app ticker handles the
  simple case.

---

## First-time setup

This repository ships the hand-authored files (Dart, Kotlin, Swift, manifests,
entitlements). Some Flutter-generated boilerplate (Xcode project files,
launcher icons, gradle wrapper JAR, LaunchScreen storyboard) is NOT committed
— regenerate it with:

```bash
cd app
flutter create . \
  --platforms=android,ios \
  --org com.lukac \
  --project-name time_rewards
flutter pub get
```

`flutter create .` is idempotent: it only writes files that are missing, so
your Dart/Kotlin/Swift sources stay intact.

You'll need:
- Flutter 3.22+
- Android Studio with Android SDK + an emulator (or a real device)
- Xcode 15+ with a paid Apple Developer account (for iOS real-device testing)

---

## Running on Android (emulator or real device)

```bash
cd app
flutter run -d android
```

On first launch, open **Settings → Time Rewards → Grant** to:

1. Allow **Usage access** (system settings screen — toggle it for this app).
2. Enable **Accessibility → Time Rewards** (system settings screen — toggle
   the service on).

Then:
1. **Blocked tab** → tick the apps to shield.
2. **Tasks tab** → add a task with a reward in minutes, then mark it done.
3. **Home tab** → tap "Spend 15m" to lift the shield for 15 minutes.

Real-device notes:
- OEMs like Xiaomi, Huawei, Oppo may kill the accessibility service in
  aggressive battery mode. Disable battery optimization for this app in
  Settings for reliable enforcement.
- The emulator works fine for development — install a few apps into it and
  add them to the blocklist to watch the HOME-action kick in.

---

## Running on iOS

**Simulator**: the UI runs fine, but `FamilyControls` authorization fails on
the simulator, so you cannot verify real shielding there. Use it for layout
and state-machine work only.

**Real device with the entitlement**:

1. Apply for the entitlement at <https://developer.apple.com/contact/request/family-controls-distribution>.
   Wait for Apple's approval (can take several weeks).
2. In Xcode → Runner → Signing & Capabilities, select your Team and add the
   Family Controls capability. Confirm `Runner.entitlements` contains
   `com.apple.developer.family-controls`.
3. Set the deployment target to iOS 16.0 (already configured in `Info.plist`).
4. Connect the device and `flutter run -d <device-id>`.

First launch: tap **Grant** on the Settings tab. iOS shows the Screen Time
authorization sheet. After approval, tap **Pick apps** on the Blocked tab to
open the Family Activity Picker and choose apps/categories to shield.

---

## Architecture

```
lib/
  main.dart                          entry
  app.dart                           MaterialApp + root state scope
  state/app_state.dart               ChangeNotifier: tasks, ledger, ticker
  models/task.dart                   TaskItem
  models/reward_ledger.dart          balanceSeconds + shieldLiftedUntil
  services/storage_service.dart      SharedPreferences persistence
  services/enforcement_service.dart  MethodChannel client
  services/calendar_service.dart     (stub) external task-source interface
  screens/home_screen.dart           dashboard + nav
  screens/tasks_screen.dart          CRUD for tasks
  screens/blocked_apps_screen.dart   Android: package list picker; iOS: FamilyActivityPicker launcher
  screens/settings_screen.dart       permissions
  widgets/reward_balance_card.dart   balance + spend buttons
  widgets/task_tile.dart             task row

android/app/src/main/
  AndroidManifest.xml                permissions, accessibility service registration
  kotlin/.../MainActivity.kt         MethodChannel handler
  kotlin/.../AppBlockerService.kt    AccessibilityService that closes blocked apps via global HOME
  res/xml/accessibility_service_config.xml

ios/Runner/
  AppDelegate.swift                  MethodChannel handler
  FamilyControlsBridge.swift         auth, picker, shield store
  Runner.entitlements                Family Controls capability
  Info.plist                         iOS 16 minimum
```

Channel: `com.lukac.timerewards/enforcement`. Methods:
- `hasPermissions` → bool
- `requestPermissions` → bool (best-effort)
- `listInstalledApps` → `[{packageName, label}]` (Android only)
- `pickApps` → bool (iOS only)
- `applyShield {packages: [String]}` → void
- `clearShield` → void

---

## Next steps

1. Wire one calendar/to-do source (start with Google Tasks — `googleapis` +
   `google_sign_in`). Poll in the background and surface items as tasks with
   a default reward.
2. Add a foreground notification service on Android so the enforcement keeps
   running when the app is backgrounded on strict OEMs.
3. Add an iOS `DeviceActivityMonitor` extension so the shield re-applies at
   the exact second the purchased time runs out, even if the app is not
   running.
4. Streak tracking / harder rewards for recurring tasks (e.g. only counts if
   completed before the calendar-event start time).
