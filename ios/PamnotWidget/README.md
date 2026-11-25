# PamnotWidget (WidgetKit extension)

Swift sources of the `PamnotWidgetExtension` target (bundle id `app.pamnot.pamnot.PamnotWidget`,
iOS 17.0), embedded in Runner. It holds two widgets:

- **Pamnot · Today**: home screen `systemSmall` / `systemMedium` / `systemLarge` and lock screen
  `accessoryRectangular` / `accessoryCircular` (done/total gauge).
- **Pamnot · List**: home screen `systemSmall` / `systemMedium` / `systemLarge`. Edit Widget picks
  a list and a box (or all four boxes); tapping a row's circle marks that task done.

| File | Purpose | Target member |
| --- | --- | --- |
| `PamnotWidgetBundle.swift` | `@main` widget bundle | Sources |
| `PamnotTodayWidget.swift` | Today widget: shared constants, model, provider, views | Sources |
| `PamnotListWidget.swift` | List widget: model, App Intent provider, views | Sources |
| `PamnotListIntents.swift` | List/box configuration intent and the "done" intent | Sources |
| `PrivacyInfo.xcprivacy` | Privacy manifest: App Group user defaults only (`1C8F.1`), no tracking, no collected data | Resources |
| `en.lproj` / `tr.lproj` `Localizable.strings` | Widget and intent texts | Resources |
| `Info.plist` | Extension Info.plist (`com.apple.widgetkit-extension`) | no (build setting) |
| `PamnotWidget.entitlements` | App Group `group.app.pamnot.shared` | no (build setting) |
| `PamnotWidget.xcconfig` | Base configuration: version numbers from `flutter build` | no (base configuration) |

Contract with the Flutter side (keep in sync with `lib/services/widget_sync*.dart`):

- App Group `group.app.pamnot.shared` (`HomeWidget.setAppGroupId`).
- Key `pamnot_today` (Today widget) and key `pamnot_lists` (List widget), JSON strings
  (`HomeWidget.saveWidgetData<String>`).
- Key `pamnot_pending_done`: ids the List widget marked done; the app applies them when it opens.
- Widget kinds `PamnotTodayWidget` and `PamnotListWidget` (`HomeWidget.updateWidget(iOSName: …)`).
- Tapping the Today widget opens `pamnot://today?homeWidget`; tapping a List widget opens
  `pamnot://list/<id>?homeWidget`. home_widget only reports URLs that carry the `homeWidget`
  query item (`HomeWidget.initiallyLaunchedFromHomeWidget()` / `HomeWidget.widgetClicked`).
- The `pamnot` scheme is also registered for `pamnot://ses` (`CFBundleURLTypes` in
  `ios/Runner/Info.plist`), which opens the add-by-voice screen. Widget links are still claimed by
  `home_widget` through `?homeWidget`. `FlutterDeepLinkingEnabled = false` is set on purpose: if it
  were on, an unclaimed `pamnot://` link would open a second home screen.

The timelines reload every 30 min. At midnight the Today widget switches to an "open the app"
placeholder, so yesterday's plan is never shown under "Today". The extension links no pods and no
Swift package, and does not import home_widget.

## How the target is added

The target is already in `ios/Runner.xcodeproj`. It was added by
`ruby tool/ios/add_widget_target.rb ios/Runner.xcodeproj` (needs the `xcodeproj` gem; running it
again changes nothing), and `ruby tool/ios/check_project.rb ios/Runner.xcodeproj` checks the
result. The script:

- creates `PamnotWidgetExtension` (app extension, iOS 17.0, Swift 5) with the four Swift files in
  Sources and `PrivacyInfo.xcprivacy` plus the en/tr `Localizable.strings` in Resources;
- sets, for Debug, Release and Profile: base configuration `PamnotWidget.xcconfig`,
  `INFOPLIST_FILE = PamnotWidget/Info.plist`, `GENERATE_INFOPLIST_FILE = NO`,
  `CODE_SIGN_ENTITLEMENTS = PamnotWidget/PamnotWidget.entitlements`, `CODE_SIGN_STYLE = Automatic`;
- leaves the Frameworks phase empty (no fixed SDK path);
- adds a Runner → PamnotWidgetExtension dependency and an **Embed Foundation Extensions** phase
  (Plugins folder) as Runner's first build phase, ahead of **Run Script** and **Thin Binary**, so
  the build has no "Cycle inside Runner";
- sets Runner's `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` (the same App Group).

No `DEVELOPMENT_TEAM` is written, for Runner or the extension. The Podfile needs no target block
for the extension; `pod install` leaves it alone.

App Groups need a paid Apple Developer membership. Runner now signs with the App Group
entitlement, so a free Personal Team can no longer sign the app as it is.

## One-time Xcode steps for the owner

After `pod install`, open `ios/Runner.xcworkspace`:

1. **PamnotWidgetExtension → Signing & Capabilities → Team:** choose your team (the same as Runner).
2. **Runner** and **PamnotWidgetExtension → Signing & Capabilities → App Groups:** check that
   `group.app.pamnot.shared` is ticked. If it is not, tick it; Xcode registers the identifier with
   your account.
3. **Product → Archive** (or `flutter build ipa`).

## Fallback: adding the target by hand

Use this only if the scripted target fails to build in Xcode.

1. Restore the project from before the target was added:
   `git checkout <commit before "Widget hedefi Runner projesine betikle eklendi"> -- ios/Runner.xcodeproj`
2. Move these sources out of the way, so Xcode can create a fresh folder:
   `mv ios/PamnotWidget /tmp/PamnotWidget-src`
3. Open `ios/Runner.xcworkspace`, then choose **File → New → Target… → iOS → Widget Extension**.
   - Product Name: `PamnotWidget`. Xcode names the target `PamnotWidgetExtension` and gives it the
     bundle id `app.pamnot.pamnot.PamnotWidget`.
   - Leave **Include Configuration App Intent** unchecked (called "Configuration Intent" in older
     Xcode), and uncheck **Include Live Activity** and **Include Control**.
   - Team: same as Runner. Embed in Application: **Runner**. Click Finish, then **Don't Activate**
     (Flutter builds the Runner scheme).
4. Delete the Swift files and `Info.plist` that Xcode generated in the `PamnotWidget` group (Move to
   Trash). Then put our files back: `cp -R /tmp/PamnotWidget-src/. ios/PamnotWidget/`
   - In older Xcode (plain groups), add the four `.swift` files, `PrivacyInfo.xcprivacy` and the
     `en.lproj` / `tr.lproj` `Localizable.strings` to the group, with target membership
     **PamnotWidgetExtension** only.
   - In Xcode 16+ (synchronized folder), the files are picked up automatically. Open the folder's
     File inspector and remove `Info.plist`, `README.md`, `PamnotWidget.xcconfig` and
     `PamnotWidget.entitlements` from target membership. Only the four `.swift` files,
     `PrivacyInfo.xcprivacy`, `Localizable.strings` and `Assets.xcassets` should be members.
   - `PrivacyInfo.xcprivacy` must be in the extension's **Copy Bundle Resources**, so that it is
     copied into the `.appex`: every extension bundle needs its own privacy manifest.
5. **PamnotWidgetExtension → General → Minimum Deployments:** iOS **17.0**.
6. **PamnotWidgetExtension → Build Settings** (all configurations):
   - Generate Info.plist File = **No**; Info.plist File = `PamnotWidget/Info.plist`
   - Code Signing Entitlements = `PamnotWidget/PamnotWidget.entitlements`
   - Swift Language Version = Swift 5. If Xcode set Default Actor Isolation to MainActor, change it
     to nonisolated.
   - Delete any target-level `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. Our Info.plist uses
     `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`.
7. **Project Runner → Info → Configurations:** for **Debug, Release and Profile**, set the
   PamnotWidgetExtension row to `PamnotWidget.xcconfig`. Leave Runner's rows untouched.
8. **Signing & Capabilities:** add **App Groups** to both **Runner** and
   **PamnotWidgetExtension**, and tick `group.app.pamnot.shared`. For Runner this sets Code Signing
   Entitlements to `Runner/Runner.entitlements`.
9. **Runner → Build Phases:** drag **Embed Foundation Extensions** (it must contain
   `PamnotWidgetExtension.appex`) to the top, above **Run Script** and **Thin Binary**.
10. Run `flutter build ios` (or run the Runner scheme) and add both widgets from the home screen.

## Reusing for macOS later

The same Swift files compile for a macOS widget target. Lock-screen families and the gauge views
are behind `#if os(iOS)`, and `containerBackground` is gated for macOS 14.

To set one up, add a **macOS → Widget Extension** target in `macos/Runner.xcodeproj` and reference
these `.swift` files. Give it its own Info.plist and entitlements: macOS widgets must be
sandboxed, so add `com.apple.security.app-sandbox` plus the same App Group, and add the App Group
to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements` as well (they leave it out
until a widget exists, so unsigned test builds of the Mac app open without a provisioning profile).

Note that home_widget has no macOS implementation. The Flutter app would have to write
`pamnot_today` / `pamnot_lists` into `UserDefaults(suiteName: "group.app.pamnot.shared")` itself,
for example via a small method channel, and reload the widget timelines.
