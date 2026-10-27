# PamukWidget (WidgetKit extension)

Swift sources for the "Pamuk · Today" widget: home screen `systemSmall` / `systemMedium` /
`systemLarge` and lock screen `accessoryRectangular` / `accessoryCircular` (done/total gauge).

| File | Purpose |
| --- | --- |
| `PamukWidgetBundle.swift` | `@main` widget bundle |
| `PamukTodayWidget.swift` | Codable model, TimelineProvider, all views |
| `Info.plist` | Extension Info.plist (`com.apple.widgetkit-extension`) |
| `PamukWidget.entitlements` | App Group `group.app.pamuk.shared` |
| `PamukWidget.xcconfig` | Base config: version numbers from `flutter build` |

Contract with the Flutter side (keep in sync):

- App Group `group.app.pamuk.shared` (`HomeWidget.setAppGroupId`).
- Key `pamuk_today`, a JSON string (`HomeWidget.saveWidgetData<String>`).
- Widget kind `PamukTodayWidget` (`HomeWidget.updateWidget(iOSName: 'PamukTodayWidget')`).
- Tapping opens `pamuk://today?homeWidget`. home_widget only reports URLs that carry the
  `homeWidget` query item (`HomeWidget.initiallyLaunchedFromHomeWidget()` /
  `HomeWidget.widgetClicked`). The `pamuk` scheme does not need to be registered.

The timeline reloads every 30 min. At midnight it switches to an "open the app" placeholder, so
yesterday's plan is never shown under "Today". The extension links no pods and does not import
home_widget.

## One-time Xcode setup

The extension target is not in `Runner.xcodeproj` yet. Editing the pbxproj by hand is
error-prone, so let Xcode create the target, then swap in these sources.

1. Move these sources out of the way, so Xcode can create a fresh folder:
   `mv ios/PamukWidget /tmp/PamukWidget-src`
2. Open `ios/Runner.xcworkspace`, then choose **File → New → Target… → iOS → Widget Extension**.
   - Product Name: `PamukWidget`. Xcode names the target `PamukWidgetExtension` and gives it the
     bundle id `app.pamuk.pamuk.PamukWidget`.
   - Uncheck **Include Live Activity**, **Include Control**, and **Include Configuration App
     Intent** (called "Configuration Intent" in older Xcode).
   - Team: same as Runner. Embed in Application: **Runner**. Click Finish, then **Don't Activate**
     (Flutter builds the Runner scheme).
3. Delete the Swift files and `Info.plist` that Xcode generated in the `PamukWidget` group (Move to
   Trash). Keep `Assets.xcassets`. Then put our files back:
   `cp /tmp/PamukWidget-src/* ios/PamukWidget/`
   - In older Xcode (plain groups), add `PamukWidgetBundle.swift` and `PamukTodayWidget.swift` to
     the group, with target membership **PamukWidgetExtension** only.
   - In Xcode 16+ (synchronized folder), the files are picked up automatically. Open the folder's
     File inspector and remove `Info.plist`, `README.md`, `PamukWidget.xcconfig` and
     `PamukWidget.entitlements` from target membership. Only the two `.swift` files and
     `Assets.xcassets` should be members.
4. **PamukWidgetExtension → General → Minimum Deployments:** iOS **16.0**.
5. **PamukWidgetExtension → Build Settings** (All configurations):
   - Generate Info.plist File = **No**; Info.plist File = `PamukWidget/Info.plist`
   - Code Signing Entitlements = `PamukWidget/PamukWidget.entitlements`
   - Swift Language Version = Swift 5. If Xcode set Default Actor Isolation to MainActor, change it
     to nonisolated.
   - Delete any target-level `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. Our Info.plist uses
     `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`.
6. **Project Runner → Info → Configurations:** for **Debug, Release and Profile**, set the
   PamukWidgetExtension row to `PamukWidget.xcconfig`. Leave Runner's rows untouched.
7. **Signing & Capabilities:** add **App Groups** to both **Runner** and
   **PamukWidgetExtension**, and tick `group.app.pamuk.shared`. Both entitlements files already
   list it; adding the capability lets Xcode register it with your team.
8. **Runner → Build Phases:** make sure **Embed Foundation Extensions** contains
   `PamukWidgetExtension.appex`. If the build fails with "Cycle inside Runner", drag that phase
   above **Thin Binary** (and above **Run Script**, if needed).
9. Run `flutter build ios` (or run the Runner scheme), add the widget from the home screen, and
   check that `HomeWidget.updateWidget(iOSName: 'PamukTodayWidget')` refreshes it.

## Reusing for macOS later

The same Swift files compile for a macOS widget target. Lock-screen families and the gauge views
are behind `#if os(iOS)`, and `containerBackground` is gated for macOS 14.

To set one up, add a **macOS → Widget Extension** target in `macos/Runner.xcodeproj` and reference
these two `.swift` files. Give it its own Info.plist and entitlements: macOS widgets must be
sandboxed, so add `com.apple.security.app-sandbox` plus the same App Group, which is already in
`macos/Runner/*.entitlements`.

Note that home_widget has no macOS implementation. The Flutter app would have to write
`pamuk_today` into `UserDefaults(suiteName: "group.app.pamuk.shared")` itself, for example via a
small method channel, and call `WidgetCenter.shared.reloadTimelines(ofKind: "PamukTodayWidget")`.
