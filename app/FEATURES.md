# Time Rewards — Functionality Spec

This document is the living spec for the app. It covers what ships in the
current MVP (✅), what is designed and queued but not yet built (🟡), and
what is open / to be refined (⬜).

---

## 1. Core loop

**Earn screen-time on chosen apps by completing real-world tasks.**

- User defines a set of **blocked apps** (distraction apps).
- User has a list of **tasks**. Each task has a reward in minutes.
- Completing a task credits the reward to a **time balance**.
- User can **spend** from the balance to **lift the shield** on blocked apps
  for a chosen duration.
- When the unlock window ends, the shield re-applies automatically.

### States in the state machine

| State | Meaning | Blocked apps behaviour |
|---|---|---|
| `idle` | No blocked apps configured | Nothing is shielded |
| `shielded` | Shield active, no unlock window | Opening a blocked app → closed |
| `unlocked` | Paid unlock window active (`shieldLiftedUntil` in future) | Blocked apps are usable |
| `expiring` | Unlock window just ended | Ticker re-applies shield, notifies UI |

Transitions are driven by:
- `completeTask(id)` → `idle/shielded → same` (only credits time)
- `spendReward(duration)` → `shielded → unlocked`
- Ticker (1 s) → `unlocked → shielded` when `DateTime.now() >= shieldLiftedUntil`
- `setBlockedApps(list)` → re-syncs shield based on current ledger

---

## 2. Tasks

### ✅ Built

- Local tasks, stored in SharedPreferences.
- Each task: `id` (UUID), `title`, `rewardMinutes` (1..60), `completed`, `createdAt`, `completedAt`.
- Add via FAB → bottom sheet (title + reward slider).
- Complete via checkbox or list-tile action. **Idempotent** — completing an
  already-completed task does not re-credit minutes.
- Delete via trash icon (tasks tab) or swipe-to-delete (planned).

### 🟡 Task-source integrations (sync from external apps)

**Goal:** let the user pick one or more external sources to pull tasks from.
Each source runs its own sync; synced tasks show in the Tasks tab alongside
local ones and carry a source badge.

**Planned sources:**

| Source | Auth | Library / API | Notes |
|---|---|---|---|
| Google Tasks | OAuth2 via `google_sign_in` | `googleapis` (`TasksApi`) | Read + mark done |
| Google Calendar | OAuth2 via `google_sign_in` | `googleapis` (`CalendarApi`) | Events as time-boxed tasks |
| Microsoft To Do | OAuth2 device flow or redirect | Microsoft Graph `/me/todo/lists` | |
| Microsoft Teams tasks | OAuth2 | Graph Planner API | Planner tasks assigned to user |
| Apple Reminders | Local only (iOS) | EventKit via `device_calendar` or a custom channel | iOS only |
| Apple Calendar | Local only (iOS) | EventKit | iOS only |
| Todoist | Personal API token | Todoist REST v2 | |
| Notion | OAuth2 + database id | Notion API | |
| Trello | OAuth1 | Trello REST | |
| ICS URL | None | Any public `.ics` feed | Generic calendar |

**UX:**
- New **Sources** tab in the bottom nav (or a section in Settings).
- List of "Available integrations" (all supported providers) with a
  "Connect" button each.
- "Connected" section shows currently linked accounts, last sync time, and
  a toggle to enable/disable. Per-connection settings: default reward
  minutes, which list/calendar to pull from, filter rules.
- Manual "Sync now" button. Background sync every N minutes while the app
  is foregrounded; on Android a periodic WorkManager task for background.

**Data shape:**
```dart
abstract class TaskSource {
  String get id;                 // stable id e.g. "google-tasks"
  String get displayName;
  Future<void> connect();        // OAuth flow
  Future<void> disconnect();
  Future<bool> isConnected();
  Future<List<ExternalTask>> fetchPending({DateTime? since});
  Future<void> markDone(String externalId);  // push completion back
}

class ExternalTask {
  final String externalId;
  final String sourceId;
  final String title;
  final DateTime? dueAt;
  final String? url;
}
```

Providers:
- `taskSourcesProvider: Provider<List<TaskSource>>` — the registry.
- `connectedSourcesProvider: AsyncNotifierProvider` — which are connected.
- `externalTasksProvider: AsyncNotifierProvider<List<ExternalTask>>` — union
  of all connected sources, refreshable.

Merging: external tasks become locally-ledgered `TaskItem`s when the user
taps "accept" (or automatically if auto-accept is on for that source), so
the reward amount is explicit per task.

---

## 3. Blocked apps

### ✅ Built

- **Android:** picker lists all user-launchable apps (`queryIntentActivities(MAIN+LAUNCHER)`). User checks apps to shield. Selections persist in SharedPreferences.
- **iOS:** picker is the system `FamilyActivityPicker` from SwiftUI; user chooses individual apps **and/or entire categories** (Social, Games, etc.). Selection is persisted to Application Support via `FamilyActivitySelection` Codable round-trip.
- Enforcement:
  - Android: `AccessibilityService` listens for `TYPE_WINDOW_STATE_CHANGED`; if the foreground package is in the blocklist and the shield is active, calls `performGlobalAction(GLOBAL_ACTION_HOME)`.
  - iOS: `ManagedSettingsStore.shield.applications` + `.applicationCategories`.

### 🟡 Always-allowed apps (allowlist during shield)

**Goal:** some apps must never be blocked — Phone, Messages, Maps, emergency
apps, medical apps, password manager, etc. Even while the shield is active,
opening these must work.

**UX:**
- In the Blocked tab, a second section: **Always allowed**. Same picker but
  the selection is subtracted from the shield.
- Suggested defaults (pre-checked): dialer, SMS, Maps, Clock. Localised
  per-device.

**Android implementation:**
- Add a second SharedPreferences key `allowed_packages`.
- `AppBlockerService.onAccessibilityEvent` filter:
  ```
  if (!shieldActive) return
  if (pkg in allowed_packages) return   // new
  if (pkg in blocked_packages) → HOME
  ```
- MainActivity channel methods:
  - `setAllowList(packages: [String])`
  - `listEssentialApps()` returns suggested defaults by resolving intent actions: `ACTION_DIAL`, `ACTION_SENDTO sms:`, `ACTION_VIEW geo:`, `ACTION_CALL` (for 911/112).

**iOS implementation:**
- FamilyControls has no "allowlist" concept inside a chosen selection — the
  selection itself defines what's shielded. To emulate: keep a separate
  `allowedSelection: FamilyActivitySelection` the user picks, and before
  applying the shield, **subtract allowed tokens from the blocked set** and
  use the result for `store.shield.applications`.
- Phone, Messages, and Emergency SOS are not shieldable by FamilyControls
  anyway (system-protected), so the minimum safety floor is already there.

Providers:
- `allowedAppsProvider: AsyncNotifierProvider<List<String>>` (Android)
  or `AsyncNotifierProvider<FamilyActivitySelection>` (iOS).
- `effectiveShieldProvider: Provider` computes `blocked − allowed` and
  drives `shieldSyncProvider`.

---

## 4. Notifications during shield

### 🟡 Suppress notifications from blocked apps while shield is active

**Goal:** when the lock is on, do not surface notifications from the apps
you are shielding — the whole point is to not think about them.

### Android

- Needs a **`NotificationListenerService`**. Separate permission from
  accessibility (user grants in Settings → Notifications → Device & app
  notifications → Special app access → Notification access).
- On `onNotificationPosted(sbn: StatusBarNotification)`:
  ```
  if (!shieldActive) return
  if (sbn.packageName in allowed_packages) return
  if (sbn.packageName in blocked_packages) cancelNotification(sbn.key)
  ```
- Silently drops matching notifications. Notifications from non-blocked apps
  are untouched.
- Manifest additions:
  ```xml
  <service android:name=".NotificationMuteService"
           android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
           android:exported="true">
      <intent-filter>
          <action android:name="android.service.notification.NotificationListenerService" />
      </intent-filter>
  </service>
  ```
- `<uses-permission android:name="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" tools:node="remove"/>` is *not* needed; the permission is implicit via the service binding.
- MainActivity: open `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` from
  the permissions flow.

### iOS

- **iOS cannot intercept or hide third-party notifications** from an app
  outside the system Focus/Screen Time features.
- Partial workaround: FamilyControls' `ManagedSettings` can **silence**
  certain notification categories, but not arbitrary per-app suppression.
- Best achievable: teach the user to pair the shield with a system **Focus
  mode**. We can suggest "Turn on Do Not Disturb while shielded" via a
  shortcut deep link (`shortcuts://`) — not automatic, but close.
- Alternative: schedule a `DeviceActivitySchedule` that activates a Shield
  and Focus simultaneously — requires the DeviceActivity extension (not in
  MVP). This is the correct long-term approach.

Providers:
- `notificationMutePermissionProvider: FutureProvider<bool>`
- The existing `shieldSyncProvider` also writes the shield-active flag into
  the SharedPreferences the Notification listener reads (Android) / toggles
  the managed settings (iOS).

---

## 5. Permissions

### ✅ Built

- Settings screen with a **Grant** button that deep-links to the right
  system settings page for each platform.
- Android: Usage Access + Accessibility service toggle.
- iOS: `FamilyControls` authorization via `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.

### 🟡 New permissions needed for the features above

| Feature | Android permission | iOS permission |
|---|---|---|
| Notification suppression | Notification Listener access | — (Focus suggestion only) |
| Always-allowed apps | none extra | none extra |
| Task-source OAuth | Internet (already declared) | Internet |
| Background sync | `POST_NOTIFICATIONS` (13+), possibly foreground service for enforcement | `BGTaskSchedulerPermittedIdentifiers` |

---

## 6. Reward ledger

### ✅ Built

- Balance in seconds, stored in SharedPreferences.
- `RewardLedger.copyWith` with explicit `clearShieldLiftedUntil` flag so
  null means "don't change" but the clear is explicit on expiry.
- Spend buttons are enabled per-duration: `Spend 30m` is disabled until the
  balance ≥ 30 min.

### 🟡 Extensions

- Allow **custom duration** via a small modal (slider 1..240 min + preset
  chips 5 / 15 / 30 / 60).
- **Daily/weekly caps** — optionally cap how much banked time can be spent
  per day to prevent binge-unlocks.
- **Expiry** — unused minutes expire at end of day / week (configurable).
- **History** — list of earn/spend events with timestamps.
- **Streaks** — track consecutive days with at least one completed task;
  small bonus reward for streak milestones.

---

## 7. Design system (modern minimalist)

### ✅ Target (being applied in the Riverpod/design pass)

- Material 3, `ColorScheme.fromSeed`, both light and dark themes.
- Typography hierarchy: large display for balance, title for section
  headers, body for content, labelSmall for chips.
- Spacing: 8 / 16 / 24 grid. Generous whitespace, no nested cards.
- Elevation: flat by default; only the reward balance card lifts slightly.
- Navigation: bottom `NavigationBar` with subtle selected indicator, no
  top shadow divider.
- Reusable primitives under `lib/widgets/ui/` (Pill, SectionHeader, etc.).

---

## 8. Architecture

### Current (post Riverpod migration, in progress)

```
ProviderScope
├── storageServiceProvider          Provider
├── enforcementServiceProvider      Provider
├── tasksProvider                   AsyncNotifierProvider<List<TaskItem>>
├── ledgerProvider                  AsyncNotifierProvider<RewardLedger>
├── blockedAppsProvider             AsyncNotifierProvider<List<String>>
├── allowedAppsProvider    🟡       AsyncNotifierProvider<List<String>>
├── permissionStatusProvider        FutureProvider<bool>
├── installedAppsProvider           FutureProvider<List<InstalledApp>>
├── shieldSyncProvider              Provider (side-effect: watches ledger + blocked + allowed → applyShield/clearShield)
├── taskSourcesProvider    🟡       Provider<List<TaskSource>>
├── connectedSourcesProvider 🟡     AsyncNotifierProvider<List<String>>
└── externalTasksProvider  🟡       AsyncNotifierProvider<List<ExternalTask>>
```

### Native bridges

- Channel: `com.lukac.timerewards/enforcement`
- Methods (current + planned):
  - ✅ `hasPermissions` → bool
  - ✅ `requestPermissions` → bool (opens system screens)
  - ✅ `listInstalledApps` → `[{packageName, label}]` (Android)
  - ✅ `pickApps` → bool (iOS — FamilyActivityPicker)
  - ✅ `applyShield {packages}` → void
  - ✅ `clearShield` → void
  - 🟡 `setAllowList {packages}` → void
  - 🟡 `listEssentialApps` → `[{packageName, label}]` (Android)
  - 🟡 `requestNotificationAccess` → bool
  - 🟡 `hasNotificationAccess` → bool

---

## 9. Build-order queue

1. ⏳ Finish Riverpod migration + modern minimalist redesign (in progress).
2. Add **allowed-apps** picker + subtract-from-shield on both platforms.
3. Add **Android notification listener service** + wire to shield state.
4. Pick the first task-source integration (recommend **Google Tasks** — simplest OAuth, cleanest API) and ship it end-to-end.
5. Add second integration (recommend **Todoist** — token-based, no OAuth dance).
6. Add remaining integrations iteratively, sharing a generic `TaskSource` adapter.
7. iOS DeviceActivity extension for exact-second re-shielding + Focus tie-in.
8. Custom-duration modal + reward history + streaks.
9. Daily/weekly caps and expiry.

---

## 10. Non-goals (for now)

- Remote sync of the ledger (your banked minutes stay on-device).
- Social / leaderboards / friends.
- Rewarding physical activity (HealthKit / Google Fit) — possible later.
- Replacing Screen Time / Digital Wellbeing wholesale; we complement them.
