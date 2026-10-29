import SwiftUI
import WidgetKit

// MARK: - Shared constants

enum PamnotShared {
  /// Must match HomeWidget.setAppGroupId(...) on the Dart side and both targets' entitlements.
  static let appGroupId = "group.app.pamnot.shared"
  /// Key written by HomeWidget.saveWidgetData<String>('pamnot_today', json).
  static let todayKey = "pamnot_today"
  /// Must match HomeWidget.updateWidget(iOSName: 'PamnotTodayWidget').
  static let widgetKind = "PamnotTodayWidget"
  /// The `homeWidget` query item is how home_widget recognises a widget launch
  /// (HomeWidget.initiallyLaunchedFromHomeWidget / HomeWidget.widgetClicked); it also keeps
  /// Flutter's own deep-link handling from treating the URL as a route.
  static let launchURL = URL(string: "pamnot://today?homeWidget")!
  static let refreshInterval: TimeInterval = 30 * 60
  static let maxItems = 6
}

// MARK: - Model (mirrors the `pamnot_today` JSON written by the Flutter app)

struct PamnotTodayItem: Codable, Hashable {
  var title: String
  var time: String
  var kind: String
  var done: Bool
  var color: String

  private enum CodingKeys: String, CodingKey {
    case title, time, kind, done, color
  }

  var displayColor: Color {
    Color(hexString: color) ?? PamnotPalette.fallback(forKind: kind)
  }
}

struct PamnotReminder: Codable, Hashable {
  var title: String
  var time: String

  private enum CodingKeys: String, CodingKey {
    case title, time
  }
}

struct PamnotToday: Codable, Hashable {
  var updatedAt: String
  var lang: String
  var title: String
  var dateLabel: String
  var done: Int
  var total: Int
  var progressLabel: String
  var emptyText: String
  var items: [PamnotTodayItem]
  var nextReminder: PamnotReminder?

  private enum CodingKeys: String, CodingKey {
    case updatedAt, lang, title, dateLabel, done, total, progressLabel, emptyText, items, nextReminder
  }

  var fraction: Double {
    total > 0 ? min(1, Double(done) / Double(total)) : 0
  }

  /// True when the data was written on an earlier calendar day (device time zone), i.e. it is
  /// yesterday's plan and must not be shown under "Today".
  func isStale(at now: Date) -> Bool {
    guard let day = PamnotToday.localDay(of: updatedAt) else { return false }
    let c = PamnotToday.calendar.dateComponents([.year, .month, .day], from: now)
    guard let y = c.year, let m = c.month, let d = c.day else { return false }
    return day < (y, m, d)
  }

  static var calendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    return cal
  }

  /// Accepts Dart's DateTime.toIso8601String() output: local ("2026-10-27T10:00:00.000") or
  /// UTC ("2026-10-27T07:00:00.000Z").
  static func localDay(of iso: String) -> (Int, Int, Int)? {
    if iso.hasSuffix("Z") {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var parsed = formatter.date(from: iso)
      if parsed == nil {
        formatter.formatOptions = [.withInternetDateTime]
        parsed = formatter.date(from: iso)
      }
      guard let date = parsed else { return nil }
      let c = calendar.dateComponents([.year, .month, .day], from: date)
      guard let y = c.year, let m = c.month, let d = c.day else { return nil }
      return (y, m, d)
    }
    let parts = iso.prefix(10).split(separator: "-")
    guard parts.count == 3,
          let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
    else { return nil }
    return (y, m, d)
  }
}

// Decoding lives in extensions so the memberwise initializers stay available. Every field is
// optional/lenient: a missing or odd value never makes the whole payload unreadable.
extension PamnotTodayItem {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = c.lenientString(.title)
    time = c.lenientString(.time)
    kind = c.lenientString(.kind)
    done = c.lenientBool(.done)
    color = c.lenientString(.color)
  }
}

extension PamnotReminder {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = c.lenientString(.title)
    time = c.lenientString(.time)
  }
}

extension PamnotToday {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    updatedAt = c.lenientString(.updatedAt)
    lang = c.lenientString(.lang)
    title = c.lenientString(.title)
    dateLabel = c.lenientString(.dateLabel)
    progressLabel = c.lenientString(.progressLabel)
    emptyText = c.lenientString(.emptyText)
    let decoded = (try? c.decodeIfPresent([PamnotTodayItem].self, forKey: .items)) ?? []
    items = Array(decoded.filter { !$0.title.isEmpty }.prefix(PamnotShared.maxItems))
    let totalValue = max(0, c.lenientInt(.total) ?? decoded.count)
    total = totalValue
    done = min(max(0, c.lenientInt(.done) ?? 0), totalValue)
    let reminder = try? c.decodeIfPresent(PamnotReminder.self, forKey: .nextReminder)
    if let reminder, !reminder.title.isEmpty {
      nextReminder = reminder
    } else {
      nextReminder = nil
    }
  }
}

private extension KeyedDecodingContainer {
  func lenientString(_ key: Key) -> String {
    if let value = try? decodeIfPresent(String.self, forKey: key) {
      return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let value = try? decodeIfPresent(Int.self, forKey: key) {
      return String(value)
    }
    return ""
  }

  func lenientInt(_ key: Key) -> Int? {
    if let value = try? decodeIfPresent(Int.self, forKey: key) {
      return value
    }
    if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite, abs(value) < 1e9 {
      return Int(value)
    }
    if let value = try? decodeIfPresent(String.self, forKey: key) {
      return Int(value)
    }
    return nil
  }

  func lenientBool(_ key: Key) -> Bool {
    if let value = try? decodeIfPresent(Bool.self, forKey: key) {
      return value
    }
    if let value = try? decodeIfPresent(Int.self, forKey: key) {
      return value != 0
    }
    return false
  }
}

enum PamnotTodayStore {
  /// Reads the JSON string home_widget stored in the shared App Group defaults.
  static func load() -> PamnotToday? {
    guard let raw = UserDefaults(suiteName: PamnotShared.appGroupId)?.string(forKey: PamnotShared.todayKey),
          let data = raw.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(PamnotToday.self, from: data)
  }
}

extension PamnotToday {
  /// Gallery / placeholder content.
  static func sample(turkish: Bool) -> PamnotToday {
    if turkish {
      return PamnotToday(
        updatedAt: "", lang: "tr", title: "Bugün", dateLabel: "27 Ekim Salı",
        done: 1, total: 3, progressLabel: "1/3 tamamlandı", emptyText: "Bugün için plan yok",
        items: [
          PamnotTodayItem(title: "Sunumu bitir", time: "09:30", kind: "task", done: true, color: "#9B8AD8"),
          PamnotTodayItem(title: "Annemi ara", time: "", kind: "reminder", done: false, color: "#F2A88A"),
          PamnotTodayItem(title: "Akşam yogası", time: "19:00", kind: "event", done: false, color: "#86C5B0"),
        ],
        nextReminder: PamnotReminder(title: "İlaç", time: "14:00")
      )
    }
    return PamnotToday(
      updatedAt: "", lang: "en", title: "Today", dateLabel: "Tuesday, 27 October",
      done: 1, total: 3, progressLabel: "1/3 done", emptyText: "Nothing planned for today",
      items: [
        PamnotTodayItem(title: "Finish the slides", time: "09:30", kind: "task", done: true, color: "#9B8AD8"),
        PamnotTodayItem(title: "Call mom", time: "", kind: "reminder", done: false, color: "#F2A88A"),
        PamnotTodayItem(title: "Evening yoga", time: "19:00", kind: "event", done: false, color: "#86C5B0"),
      ],
      nextReminder: PamnotReminder(title: "Medicine", time: "14:00")
    )
  }
}

// MARK: - Strings drawn by the widget itself (everything else comes localized from the app)

struct PamnotStrings {
  let turkish: Bool

  /// Uses the app's language from the payload when known, otherwise the device language.
  init(lang: String?) {
    if let lang, !lang.isEmpty {
      turkish = lang.lowercased().hasPrefix("tr")
    } else {
      turkish = PamnotStrings.deviceIsTurkish
    }
  }

  static var deviceIsTurkish: Bool {
    (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("tr")
  }

  var placeholderText: String { turkish ? "Uygulamayı açarak başlayın" : "Open the app to get started" }
  var staleText: String { turkish ? "Bugünün planı için uygulamayı açın" : "Open the app to see today's plan" }
  var defaultTitle: String { turkish ? "Bugün" : "Today" }
  var emptyFallback: String { turkish ? "Bugün için plan yok" : "Nothing planned for today" }
  var next: String { turkish ? "Sıradaki" : "Next" }
  var displayName: String { turkish ? "Pamnot · Bugün" : "Pamnot · Today" }
  var widgetDescription: String {
    turkish
      ? "Bugünün planı, görevleri ve anımsatıcıları bir bakışta."
      : "Today's plan, tasks and reminders at a glance."
  }

  func more(_ count: Int) -> String { turkish ? "+\(count) daha" : "+\(count) more" }
}

// MARK: - Timeline

struct PamnotTodayEntry: TimelineEntry {
  let date: Date
  /// nil = the app has not written (valid) data yet.
  let today: PamnotToday?
  let isStale: Bool

  /// The data to draw, or nil when the placeholder ("Pamnot" + message) must be shown.
  var visibleToday: PamnotToday? { isStale ? nil : today }
  var strings: PamnotStrings { PamnotStrings(lang: today?.lang) }
  var message: String { today == nil ? strings.placeholderText : strings.staleText }
}

struct PamnotTodayProvider: TimelineProvider {
  func placeholder(in context: Context) -> PamnotTodayEntry {
    PamnotTodayEntry(date: Date(), today: .sample(turkish: PamnotStrings.deviceIsTurkish), isStale: false)
  }

  func getSnapshot(in context: Context, completion: @escaping (PamnotTodayEntry) -> Void) {
    let now = Date()
    if let stored = PamnotTodayStore.load() {
      completion(PamnotTodayEntry(date: now, today: stored, isStale: stored.isStale(at: now)))
    } else if context.isPreview {
      completion(placeholder(in: context))
    } else {
      completion(PamnotTodayEntry(date: now, today: nil, isStale: false))
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PamnotTodayEntry>) -> Void) {
    let now = Date()
    let stored = PamnotTodayStore.load()
    var entries = [PamnotTodayEntry(date: now, today: stored, isStale: stored?.isStale(at: now) ?? false)]
    // At midnight the stored plan becomes yesterday's; switch to the "open the app" state then,
    // even if WidgetKit postpones the next reload.
    if let stored, !stored.isStale(at: now) {
      let cal = PamnotToday.calendar
      if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
        entries.append(PamnotTodayEntry(date: midnight, today: stored, isStale: true))
      }
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(PamnotShared.refreshInterval))))
  }
}

// MARK: - Widget

struct PamnotTodayWidget: Widget {
  let kind: String = PamnotShared.widgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PamnotTodayProvider()) { entry in
      PamnotTodayWidgetView(entry: entry)
    }
    .configurationDisplayName(PamnotStrings(lang: nil).displayName)
    .description(PamnotStrings(lang: nil).widgetDescription)
    .supportedFamilies(PamnotTodayWidget.families)
  }

  static var families: [WidgetFamily] {
    #if os(iOS)
    return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular]
    #else
    return [.systemSmall, .systemMedium, .systemLarge]
    #endif
  }
}

// MARK: - Palette

enum PamnotPalette {
  static let lavender = Color(hex: 0x9B8AD8)
  static let peach = Color(hex: 0xF2A88A)
  static let mint = Color(hex: 0x86C5B0)

  static func fallback(forKind kind: String) -> Color {
    switch kind {
    case "reminder": return peach
    case "event": return mint
    default: return lavender
    }
  }
}

struct PamnotColors {
  let background: Color
  let text: Color
  let secondary: Color
  let accentText: Color
  let track: Color
  let pill: Color
  let peachPill: Color

  init(_ scheme: ColorScheme) {
    let dark = scheme == .dark
    background = Color(hex: dark ? 0x24212B : 0xFBF7F2)
    text = Color(hex: dark ? 0xECE8F4 : 0x3E3A4A)
    secondary = Color(hex: dark ? 0xA39DB2 : 0x8C8698)
    accentText = Color(hex: dark ? 0xB9ACEB : 0x7A68C2)
    track = Color(hex: dark ? 0x363140 : 0xEFE8F6)
    pill = PamnotPalette.lavender.opacity(dark ? 0.2 : 0.14)
    peachPill = PamnotPalette.peach.opacity(dark ? 0.2 : 0.18)
  }

  var textDone: Color { text.opacity(0.4) }
  var secondaryDone: Color { secondary.opacity(0.4) }
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }

  /// "#RRGGBB" or "#AARRGGBB" (Flutter/Android order); nil when unparsable.
  init?(hexString: String) {
    var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
    if value.count == 8 {
      self.init(hex: UInt32(number & 0xFFFFFF), opacity: Double((number >> 24) & 0xFF) / 255)
    } else {
      self.init(hex: UInt32(number))
    }
  }
}

// MARK: - Views

struct PamnotTodayWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  let entry: PamnotTodayEntry

  var body: some View {
    familyView
      .widgetURL(PamnotShared.launchURL)
  }

  @ViewBuilder
  private var familyView: some View {
    let colors = PamnotColors(colorScheme)
    switch family {
    case .systemSmall:
      PamnotSmallView(entry: entry, colors: colors)
        .pamnotContainer(fallbackPadding: 15, colors.background)
    case .systemMedium:
      PamnotMediumView(entry: entry, colors: colors)
        .pamnotContainer(fallbackPadding: 16, colors.background)
    case .systemLarge:
      PamnotLargeView(entry: entry, colors: colors)
        .pamnotContainer(fallbackPadding: 16, colors.background)
    default:
      PamnotAccessoryView(entry: entry, family: family, colors: colors)
    }
  }
}

/// Lock-screen families on iOS; falls back to the medium layout elsewhere (e.g. a future macOS target).
struct PamnotAccessoryView: View {
  let entry: PamnotTodayEntry
  let family: WidgetFamily
  let colors: PamnotColors

  var body: some View {
    #if os(iOS)
    if family == .accessoryCircular {
      PamnotCircularView(entry: entry)
        .pamnotContainer(fallbackPadding: 0, Color.clear)
    } else {
      PamnotRectangularView(entry: entry)
        .pamnotContainer(fallbackPadding: 0, Color.clear)
    }
    #else
    PamnotMediumView(entry: entry, colors: colors)
      .pamnotContainer(fallbackPadding: 16, colors.background)
    #endif
  }
}

private extension View {
  /// iOS 17+ / macOS 14+: containerBackground (the system adds the standard content margins).
  /// iOS 16: plain background plus equivalent padding.
  @ViewBuilder
  func pamnotContainer(fallbackPadding: CGFloat, _ backdrop: some View) -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      containerBackground(for: .widget) {
        backdrop
      }
    } else {
      padding(fallbackPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdrop)
    }
  }
}

struct PamnotSmallView: View {
  let entry: PamnotTodayEntry
  let colors: PamnotColors

  var body: some View {
    if let today = entry.visibleToday {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(today.title.isEmpty ? entry.strings.defaultTitle : today.title)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(colors.text)
            .lineLimit(1)
          Spacer(minLength: 2)
          if today.total > 0 {
            Text(verbatim: "\(today.done)/\(today.total)")
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .monospacedDigit()
              .foregroundColor(colors.accentText)
          }
        }
        if !today.dateLabel.isEmpty {
          Text(today.dateLabel)
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(colors.secondary)
            .lineLimit(1)
            .padding(.top, 1)
        }
        Spacer(minLength: 6)
        PamnotItemList(
          today: today, strings: entry.strings, colors: colors,
          maxRows: 3, fontSize: 12, spacing: 5, showTime: true
        )
        Spacer(minLength: 6)
        if today.total > 0 {
          PamnotProgressBar(fraction: today.fraction, height: 5, track: colors.track)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      PamnotPlaceholderView(message: entry.message, colors: colors, compact: true)
    }
  }
}

struct PamnotMediumView: View {
  let entry: PamnotTodayEntry
  let colors: PamnotColors

  var body: some View {
    if let today = entry.visibleToday {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 5) {
            PamnotGlyph(color: PamnotPalette.lavender, size: 15)
            Text(today.title.isEmpty ? entry.strings.defaultTitle : today.title)
              .font(.system(size: 17, weight: .semibold, design: .rounded))
              .foregroundColor(colors.text)
              .lineLimit(1)
          }
          if !today.dateLabel.isEmpty {
            Text(today.dateLabel)
              .font(.system(size: 12, design: .rounded))
              .foregroundColor(colors.secondary)
              .lineLimit(2)
              .padding(.top, 3)
          }
          Spacer(minLength: 6)
          if !today.progressLabel.isEmpty {
            Text(today.progressLabel)
              .font(.system(size: 11, weight: .semibold, design: .rounded))
              .foregroundColor(colors.accentText)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          if today.total > 0 {
            PamnotProgressBar(fraction: today.fraction, height: 6, track: colors.track)
              .padding(.top, 5)
          }
        }
        .frame(width: 112, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)

        PamnotItemList(
          today: today, strings: entry.strings, colors: colors,
          maxRows: 4, fontSize: 13, spacing: 7, showTime: true
        )
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      PamnotPlaceholderView(message: entry.message, colors: colors, compact: false)
    }
  }
}

struct PamnotLargeView: View {
  let entry: PamnotTodayEntry
  let colors: PamnotColors

  var body: some View {
    if let today = entry.visibleToday {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 8) {
          PamnotGlyph(color: PamnotPalette.lavender, size: 22)
          VStack(alignment: .leading, spacing: 1) {
            Text(today.title.isEmpty ? entry.strings.defaultTitle : today.title)
              .font(.system(size: 20, weight: .semibold, design: .rounded))
              .foregroundColor(colors.text)
              .lineLimit(1)
            if !today.dateLabel.isEmpty {
              Text(today.dateLabel)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(colors.secondary)
                .lineLimit(1)
            }
          }
          Spacer(minLength: 6)
          if !today.progressLabel.isEmpty {
            Text(today.progressLabel)
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundColor(colors.accentText)
              .lineLimit(1)
              .padding(.horizontal, 9)
              .padding(.vertical, 4)
              .background(colors.pill, in: Capsule())
          }
        }
        if today.total > 0 {
          PamnotProgressBar(fraction: today.fraction, height: 7, track: colors.track)
            .padding(.top, 12)
        }
        PamnotItemList(
          today: today, strings: entry.strings, colors: colors,
          maxRows: PamnotShared.maxItems, fontSize: 15, spacing: 10, showTime: true
        )
        .padding(.top, 14)
        Spacer(minLength: 8)
        if let next = today.nextReminder {
          PamnotNextReminderPill(reminder: next, strings: entry.strings, colors: colors)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      PamnotPlaceholderView(message: entry.message, colors: colors, compact: false)
    }
  }
}

struct PamnotItemList: View {
  let today: PamnotToday
  let strings: PamnotStrings
  let colors: PamnotColors
  let maxRows: Int
  let fontSize: CGFloat
  let spacing: CGFloat
  let showTime: Bool

  var body: some View {
    let items = today.items
    // When not everything fits, keep the last line for "+N more".
    let shown = items.count > maxRows ? max(1, maxRows - 1) : items.count
    let hidden = items.count - shown
    VStack(alignment: .leading, spacing: spacing) {
      if items.isEmpty {
        Text(today.emptyText.isEmpty ? strings.emptyFallback : today.emptyText)
          .font(.system(size: fontSize, design: .rounded))
          .foregroundColor(colors.secondary)
          .lineLimit(3)
      } else {
        ForEach(0..<shown, id: \.self) { index in
          PamnotItemRow(item: items[index], colors: colors, fontSize: fontSize, showTime: showTime)
        }
        if hidden > 0 {
          Text(strings.more(hidden))
            .font(.system(size: fontSize - 1, design: .rounded))
            .foregroundColor(colors.secondary)
            .padding(.leading, fontSize * 0.55 + 7)
        }
      }
    }
  }
}

struct PamnotItemRow: View {
  let item: PamnotTodayItem
  let colors: PamnotColors
  let fontSize: CGFloat
  let showTime: Bool

  var body: some View {
    HStack(spacing: 7) {
      PamnotMarker(kind: item.kind, color: item.displayColor, size: fontSize * 0.55)
        .opacity(item.done ? 0.45 : 1)
      Text(item.title)
        .font(.system(size: fontSize, design: .rounded))
        .strikethrough(item.done, color: colors.textDone)
        .foregroundColor(item.done ? colors.textDone : colors.text)
        .lineLimit(1)
      Spacer(minLength: 4)
      if showTime && !item.time.isEmpty {
        Text(item.time)
          .font(.system(size: fontSize - 1, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundColor(item.done ? colors.secondaryDone : colors.secondary)
          .lineLimit(1)
          .layoutPriority(1)
      }
    }
  }
}

/// task = dot, reminder = ring, event = rounded square; tinted with the item's colour.
struct PamnotMarker: View {
  let kind: String
  let color: Color
  let size: CGFloat

  var body: some View {
    switch kind {
    case "reminder":
      Circle()
        .strokeBorder(color, lineWidth: max(1.5, size * 0.28))
        .frame(width: size, height: size)
    case "event":
      RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        .fill(color)
        .frame(width: size, height: size)
    default:
      Circle()
        .fill(color)
        .frame(width: size, height: size)
    }
  }
}

struct PamnotProgressBar: View {
  let fraction: Double
  let height: CGFloat
  let track: Color

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(track)
        if fraction > 0 {
          Capsule()
            .fill(
              LinearGradient(
                colors: [PamnotPalette.lavender, PamnotPalette.mint],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(width: max(height, proxy.size.width * CGFloat(fraction)))
            .widgetAccentable()
        }
      }
    }
    .frame(height: height)
  }
}

struct PamnotNextReminderPill: View {
  let reminder: PamnotReminder
  let strings: PamnotStrings
  let colors: PamnotColors

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "bell.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(PamnotPalette.peach)
      Text(verbatim: label)
        .font(.system(size: 12, design: .rounded))
        .foregroundColor(colors.text)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(colors.peachPill, in: Capsule())
  }

  private var label: String {
    reminder.time.isEmpty
      ? "\(strings.next) · \(reminder.title)"
      : "\(strings.next) · \(reminder.time)  \(reminder.title)"
  }
}

struct PamnotPlaceholderView: View {
  let message: String
  let colors: PamnotColors
  let compact: Bool

  var body: some View {
    VStack(spacing: 6) {
      PamnotGlyph(color: PamnotPalette.lavender, size: compact ? 26 : 32)
      Text(verbatim: "Pamnot")
        .font(.system(size: compact ? 15 : 17, weight: .semibold, design: .rounded))
        .foregroundColor(colors.text)
      Text(message)
        .font(.system(size: 12, design: .rounded))
        .foregroundColor(colors.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// The Pamnot cloud puff (same geometry as Android's ic_stat_pamnot, on a 24-unit grid).
struct PamnotGlyph: View {
  let color: Color
  let size: CGFloat

  var body: some View {
    PamnotGlyphShape()
      .fill(color)
      .frame(width: size, height: size)
  }
}

struct PamnotGlyphShape: Shape {
  func path(in rect: CGRect) -> Path {
    let unit = min(rect.width, rect.height) / 24
    let originX = rect.midX - 12 * unit
    let originY = rect.midY - 12 * unit
    let circles: [(CGFloat, CGFloat, CGFloat)] = [
      (12, 10.25, 5.5), (7, 12.75, 4.2), (17, 12.75, 4.2), (12, 14.75, 4.5),
    ]
    var path = Path()
    for (cx, cy, r) in circles {
      path.addEllipse(in: CGRect(
        x: originX + (cx - r) * unit,
        y: originY + (cy - r) * unit,
        width: 2 * r * unit,
        height: 2 * r * unit
      ))
    }
    return path
  }
}

#if os(iOS)
/// Lock screen: done/total as a capacity gauge.
struct PamnotCircularView: View {
  let entry: PamnotTodayEntry

  var body: some View {
    if let today = entry.visibleToday, today.total > 0 {
      Gauge(value: Double(today.done), in: 0...Double(today.total)) {
        Image(systemName: "checkmark")
      } currentValueLabel: {
        Text(verbatim: "\(today.done)/\(today.total)")
          .minimumScaleFactor(0.5)
      }
      .gaugeStyle(.accessoryCircularCapacity)
    } else {
      ZStack {
        AccessoryWidgetBackground()
        PamnotGlyph(color: .primary, size: 26)
      }
    }
  }
}

/// Lock screen: title + count, next reminder (or first open item), progress.
struct PamnotRectangularView: View {
  let entry: PamnotTodayEntry

  var body: some View {
    if let today = entry.visibleToday {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(today.title.isEmpty ? entry.strings.defaultTitle : today.title)
            .font(.headline)
            .lineLimit(1)
          Spacer(minLength: 2)
          if today.total > 0 {
            Text(verbatim: "\(today.done)/\(today.total)")
              .font(.caption)
              .monospacedDigit()
          }
        }
        detail(today)
        if today.total > 0 {
          Gauge(value: today.fraction) {
            EmptyView()
          }
          .gaugeStyle(.accessoryLinearCapacity)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: "Pamnot")
          .font(.headline)
        Text(entry.message)
          .font(.caption)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func detail(_ today: PamnotToday) -> some View {
    if let next = today.nextReminder {
      Label {
        Text(verbatim: next.time.isEmpty ? next.title : "\(next.time) \(next.title)")
      } icon: {
        Image(systemName: "bell.fill")
      }
      .font(.caption)
      .lineLimit(1)
    } else if let item = today.items.first(where: { !$0.done }) {
      Text(verbatim: item.time.isEmpty ? item.title : "\(item.time) \(item.title)")
        .font(.caption)
        .lineLimit(1)
    } else if today.items.isEmpty {
      Text(today.emptyText.isEmpty ? entry.strings.emptyFallback : today.emptyText)
        .font(.caption)
        .lineLimit(1)
    }
  }
}
#endif

// MARK: - Previews

#if DEBUG
struct PamnotTodayWidget_Previews: PreviewProvider {
  static let entry = PamnotTodayEntry(date: Date(), today: .sample(turkish: true), isStale: false)
  static let empty = PamnotTodayEntry(date: Date(), today: nil, isStale: false)

  static var previews: some View {
    Group {
      PamnotTodayWidgetView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemSmall))
      PamnotTodayWidgetView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemMedium))
      PamnotTodayWidgetView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemLarge))
      PamnotTodayWidgetView(entry: empty)
        .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
  }
}
#endif
