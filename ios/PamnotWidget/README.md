# PamnotWidget (WidgetKit extension)

Swift sources for the "Pamnot · Today" widget: home screen `systemSmall` / `systemMedium` /
`systemLarge` and lock screen `accessoryRectangular` / `accessoryCircular` (done/total gauge).

| File | Purpose |
| --- | --- |
| `PamnotWidgetBundle.swift` | `@main` widget bundle |
| `PamnotTodayWidget.swift` | Codable model, TimelineProvider, all views |
| `Info.plist` | Extension Info.plist (`com.apple.widgetkit-extension`) |
| `PamnotWidget.entitlements` | App Group `group.app.pamnot.shared` |
| `PamnotWidget.xcconfig` | Base config: version numbers from `flutter build` |

Contract with the Flutter side (keep in sync):

- App Group `group.app.pamnot.shared` (`HomeWidget.setAppGroupId`).
- Key `pamnot_today`, a JSON string (`HomeWidget.saveWidgetData<String>`).
- Widget kind `PamnotTodayWidget` (`HomeWidget.updateWidget(iOSName: 'PamnotTodayWidget')`).
- Tapping opens `pamnot://today?homeWidget`. home_widget only reports URLs that carry the
  `homeWidget` query item (`HomeWidget.initiallyLaunchedFromHomeWidget()` /
  `HomeWidget.widgetClicked`). The `pamnot` scheme does not need to be registered.

The timeline reloads every 30 min. At midnight it switches to an "open the app" placeholder, so
yesterday's plan is never shown under "Today". The extension links no pods and does not import
home_widget.

## One-time Xcode setup

The extension target is not in `Runner.xcodeproj` yet. Editing the pbxproj by hand is
error-prone, so let Xcode create the target, then swap in these sources.

1. Move these sources out of the way, so Xcode can create a fresh folder:
   `mv ios/PamnotWidget /tmp/PamnotWidget-src`
2. Open `ios/Runner.xcworkspace`, then choose **File → New → Target… → iOS → Widget Extension**.
   - Product Name: `PamnotWidget`. Xcode names the target `PamnotWidgetExtension` and gives it the
     bundle id `app.pamnot.pamnot.PamnotWidget`.
   - Uncheck **Include Live Activity**, **Include Control**, and **Include Configuration App
     Intent** (called "Configuration Intent" in older Xcode).
   - Team: same as Runner. Embed in Application: **Runner**. Click Finish, then **Don't Activate**
     (Flutter builds the Runner scheme).
3. Delete the Swift files and `Info.plist` that Xcode generated in the `PamnotWidget` group (Move to
   Trash). Keep `Assets.xcassets`. Then put our files back:
   `cp /tmp/PamnotWidget-src/* ios/PamnotWidget/`
   - In older Xcode (plain groups), add `PamnotWidgetBundle.swift` and `PamnotTodayWidget.swift` to
     the group, with target membership **PamnotWidgetExtension** only.
   - In Xcode 16+ (synchronized folder), the files are picked up automatically. Open the folder's
     File inspector and remove `Info.plist`, `README.md`, `PamnotWidget.xcconfig` and
     `PamnotWidget.entitlements` from target membership. Only the two `.swift` files and
     `Assets.xcassets` should be members.
4. **PamnotWidgetExtension → General → Minimum Deployments:** iOS **16.0**.
5. **PamnotWidgetExtension → Build Settings** (All configurations):
   - Generate Info.plist File = **No**; Info.plist File = `PamnotWidget/Info.plist`
   - Code Signing Entitlements = `PamnotWidget/PamnotWidget.entitlements`
   - Swift Language Version = Swift 5. If Xcode set Default Actor Isolation to MainActor, change it
     to nonisolated.
   - Delete any target-level `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. Our Info.plist uses
     `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`.
6. **Project Runner → Info → Configurations:** for **Debug, Release and Profile**, set the
   PamnotWidgetExtension row to `PamnotWidget.xcconfig`. Leave Runner's rows untouched.
7. **Signing & Capabilities:** add **App Groups** to both **Runner** and
   **PamnotWidgetExtension**, and tick `group.app.pamnot.shared`. Both entitlements files already
   list it; adding the capability lets Xcode register it with your team.
8. **Runner → Build Phases:** make sure **Embed Foundation Extensions** contains
   `PamnotWidgetExtension.appex`. If the build fails with "Cycle inside Runner", drag that phase
   above **Thin Binary** (and above **Run Script**, if needed).
9. Run `flutter build ios` (or run the Runner scheme), add the widget from the home screen, and
   check that `HomeWidget.updateWidget(iOSName: 'PamnotTodayWidget')` refreshes it.

## Reusing for macOS later

The same Swift files compile for a macOS widget target. Lock-screen families and the gauge views
are behind `#if os(iOS)`, and `containerBackground` is gated for macOS 14.

To set one up, add a **macOS → Widget Extension** target in `macos/Runner.xcodeproj` and reference
these two `.swift` files. Give it its own Info.plist and entitlements: macOS widgets must be
sandboxed, so add `com.apple.security.app-sandbox` plus the same App Group, which is already in
`macos/Runner/*.entitlements`.

Note that home_widget has no macOS implementation. The Flutter app would have to write
`pamnot_today` into `UserDefaults(suiteName: "group.app.pamnot.shared")` itself, for example via a
small method channel, and call `WidgetCenter.shared.reloadTimelines(ofKind: "PamnotTodayWidget")`.
