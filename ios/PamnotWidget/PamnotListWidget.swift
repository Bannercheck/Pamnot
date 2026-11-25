import AppIntents
import SwiftUI
import WidgetKit

// The list widget: one list's open tasks by box. Tapping a row finishes the task
// (PamnotCompleteTaskIntent); tapping anywhere else opens that list in the app.

// MARK: - Model (mirrors the `pamnot_lists` JSON written by AppController.listsSummary)

struct PamnotListItem: Codable, Hashable, Identifiable {
  var id: String
  var title: String
  var time: String

  private enum CodingKeys: String, CodingKey {
    case id, title, time
  }
}

struct PamnotBoxSummary: Codable, Hashable {
  /// Open tasks in the box; `items` holds at most six of them.
  var count: Int
  var items: [PamnotListItem]

  private enum CodingKeys: String, CodingKey {
    case count, items
  }

  static let empty = PamnotBoxSummary(count: 0, items: [])
}

struct PamnotListSummary: Codable, Hashable {
  var id: String
  var name: String
  var color: String
  var boxes: [String: PamnotBoxSummary]

  private enum CodingKeys: String, CodingKey {
    case id, name, color, boxes
  }

  func box(_ choice: PamnotBoxChoice) -> PamnotBoxSummary {
    boxes[choice.rawValue] ?? .empty
  }

  /// Open tasks in all four boxes.
  var totalCount: Int {
    PamnotBoxChoice.boxes.reduce(0) { $0 + box($1).count }
  }

  /// The listed tasks of all four boxes, in matrix order.
  var allItems: [PamnotListItem] {
    PamnotBoxChoice.boxes.flatMap { box($0).items }
  }
}

struct PamnotListLabels: Codable, Hashable {
  var all: String
  var empty: String
  var appName: String

  private enum CodingKeys: String, CodingKey {
    case all, empty, appName
  }
}

struct PamnotListsPayload: Codable, Hashable {
  var updatedAt: String
  var lang: String
  var labels: PamnotListLabels
  /// Box key -> title in the app's language.
  var boxes: [String: String]
  var lists: [PamnotListSummary]

  private enum CodingKeys: String, CodingKey {
    case updatedAt, lang, labels, boxes, lists
  }

  func list(id: String?) -> PamnotListSummary? {
    if let id, let match = lists.first(where: { $0.id == id }) { return match }
    return lists.first
  }

  func title(of choice: PamnotBoxChoice) -> String {
    if choice == .all { return labels.all.isEmpty ? choice.fallbackTitle : labels.all }
    let title = boxes[choice.rawValue] ?? ""
    return title.isEmpty ? choice.fallbackTitle : title
  }

  var emptyText: String {
    labels.empty.isEmpty ? String(localized: "No tasks") : labels.empty
  }
}

// Lenient decoding: a missing or odd field never makes the whole payload unreadable.
extension PamnotListItem {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = c.listString(.id)
    title = c.listString(.title)
    time = c.listString(.time)
  }
}

extension PamnotBoxSummary {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let decoded = (try? c.decodeIfPresent([PamnotListItem].self, forKey: .items)) ?? []
    items = Array(decoded.filter { !$0.id.isEmpty && !$0.title.isEmpty }.prefix(PamnotShared.maxItems))
    count = max(items.count, c.listInt(.count) ?? items.count)
  }
}

extension PamnotListSummary {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = c.listString(.id)
    name = c.listString(.name)
    color = c.listString(.color)
    boxes = (try? c.decodeIfPresent([String: PamnotBoxSummary].self, forKey: .boxes)) ?? [:]
  }
}

extension PamnotListLabels {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    all = c.listString(.all)
    empty = c.listString(.empty)
    appName = c.listString(.appName)
  }
}

extension PamnotListsPayload {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    updatedAt = c.listString(.updatedAt)
    lang = c.listString(.lang)
    labels = (try? c.decodeIfPresent(PamnotListLabels.self, forKey: .labels))
      ?? PamnotListLabels(all: "", empty: "", appName: "")
    boxes = (try? c.decodeIfPresent([String: String].self, forKey: .boxes)) ?? [:]
    let decoded = (try? c.decodeIfPresent([PamnotListSummary].self, forKey: .lists)) ?? []
    lists = decoded.filter { !$0.id.isEmpty }
  }
}

private extension KeyedDecodingContainer {
  func listString(_ key: Key) -> String {
    if let value = try? decodeIfPresent(String.self, forKey: key) {
      return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let value = try? decodeIfPresent(Int.self, forKey: key) {
      return String(value)
    }
    return ""
  }

  func listInt(_ key: Key) -> Int? {
    if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
    if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite, abs(value) < 1e9 {
      return Int(value)
    }
    if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
    return nil
  }
}

enum PamnotListStore {
  /// The summary home_widget stored in the shared App Group defaults; nil when missing,
  /// unreadable or without lists.
  static func load() -> PamnotListsPayload? {
    guard let raw = UserDefaults(suiteName: PamnotShared.appGroupId)?.string(forKey: PamnotShared.listsKey),
          let data = raw.data(using: .utf8),
          let payload = try? JSONDecoder().decode(PamnotListsPayload.self, from: data),
          !payload.lists.isEmpty
    else { return nil }
    return payload
  }
}

extension PamnotListsPayload {
  /// Gallery / placeholder content.
  static func sample(turkish: Bool) -> PamnotListsPayload {
    func item(_ id: String, _ tr: String, _ en: String, _ time: String = "") -> PamnotListItem {
      PamnotListItem(id: id, title: turkish ? tr : en, time: time)
    }
    let boxes: [String: PamnotBoxSummary] = [
      "doNow": PamnotBoxSummary(count: 2, items: [
        item("s1", "Sunumu bitir", "Finish the slides", "09:30"),
        item("s2", "Faturayı öde", "Pay the bill"),
      ]),
      "plan": PamnotBoxSummary(count: 3, items: [
        item("s3", "Spor planı yap", "Plan workouts"),
        item("s4", "Kitap oku", "Read a book", "21:00"),
        item("s5", "Tatil araştır", "Look up holidays"),
      ]),
      "delegate": PamnotBoxSummary(count: 1, items: [item("s6", "Kargo takibi", "Track the parcel")]),
      "later": PamnotBoxSummary(count: 1, items: [item("s7", "Dolabı düzenle", "Tidy the wardrobe")]),
    ]
    return PamnotListsPayload(
      updatedAt: "", lang: turkish ? "tr" : "en",
      labels: PamnotListLabels(all: turkish ? "Tümü" : "All", empty: turkish ? "Görev yok" : "No tasks", appName: "Pamnot"),
      boxes: turkish
        ? ["doNow": "Önemli · Acil", "plan": "Önemli · Planlı", "delegate": "Acil · Önemsiz", "later": "Sonra · Belki"]
        : ["doNow": "Important · Urgent", "plan": "Important · Planned", "delegate": "Urgent · Less important", "later": "Later · Maybe"],
      lists: [PamnotListSummary(id: "personal", name: turkish ? "Kişisel" : "Personal", color: "#9B8AD8", boxes: boxes)]
    )
  }
}

// MARK: - Timeline

struct PamnotListEntry: TimelineEntry {
  let date: Date
  /// nil = the app has not written (valid) data yet.
  let payload: PamnotListsPayload?
  /// The configured list; nil or unknown = the first list.
  let listId: String?
  let box: PamnotBoxChoice

  var list: PamnotListSummary? { payload?.list(id: listId) }

  /// pamnot://list/<id>?homeWidget opens that list on the Matrix tab; without data, the app.
  var url: URL {
    guard let id = list?.id,
          let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "pamnot://list/\(encoded)?homeWidget")
    else { return PamnotShared.launchURL }
    return url
  }
}

struct PamnotListProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> PamnotListEntry {
    PamnotListEntry(date: Date(), payload: .sample(turkish: PamnotStrings.deviceIsTurkish), listId: nil, box: .all)
  }

  func snapshot(for configuration: PamnotListConfigIntent, in context: Context) async -> PamnotListEntry {
    if let stored = PamnotListStore.load() {
      return PamnotListEntry(date: Date(), payload: stored, listId: configuration.list?.id, box: configuration.box)
    }
    if context.isPreview {
      return PamnotListEntry(
        date: Date(), payload: .sample(turkish: PamnotStrings.deviceIsTurkish), listId: nil, box: configuration.box
      )
    }
    return PamnotListEntry(date: Date(), payload: nil, listId: nil, box: configuration.box)
  }

  func timeline(for configuration: PamnotListConfigIntent, in context: Context) async -> Timeline<PamnotListEntry> {
    let now = Date()
    let entry = PamnotListEntry(
      date: now, payload: PamnotListStore.load(), listId: configuration.list?.id, box: configuration.box
    )
    return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(PamnotShared.refreshInterval)))
  }
}

// MARK: - Widget

struct PamnotListWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: PamnotShared.listWidgetKind,
      intent: PamnotListConfigIntent.self,
      provider: PamnotListProvider()
    ) { entry in
      PamnotListWidgetView(entry: entry)
    }
    .configurationDisplayName("Pamnot · List")
    .description("Open tasks of a list by box. Tap a task to finish it.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - Views

/// Font size and row height per family; rows are as tall as the family allows.
struct PamnotListMetrics {
  let titleSize: CGFloat
  let headerSize: CGFloat
  let rowSize: CGFloat
  let rowHeight: CGFloat

  init(_ family: WidgetFamily) {
    switch family {
    case .systemLarge:
      self.init(titleSize: 17, headerSize: 12, rowSize: 14, rowHeight: 30)
    case .systemMedium:
      self.init(titleSize: 14, headerSize: 11, rowSize: 13, rowHeight: 24)
    default:
      self.init(titleSize: 14, headerSize: 11, rowSize: 13, rowHeight: 24)
    }
  }

  init(titleSize: CGFloat, headerSize: CGFloat, rowSize: CGFloat, rowHeight: CGFloat) {
    self.titleSize = titleSize
    self.headerSize = headerSize
    self.rowSize = rowSize
    self.rowHeight = rowHeight
  }
}

struct PamnotListWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: PamnotListEntry

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .containerBackground(for: .widget) {
        Color(uiColor: .systemBackground)
      }
      .widgetURL(entry.url)
  }

  @ViewBuilder
  private var content: some View {
    if let payload = entry.payload, let list = entry.list {
      let metrics = PamnotListMetrics(family)
      if entry.box == .all {
        switch family {
        case .systemMedium:
          PamnotAllMediumView(payload: payload, list: list, metrics: metrics)
        case .systemLarge:
          PamnotAllLargeView(payload: payload, list: list, metrics: metrics)
        default:
          PamnotAllSmallView(payload: payload, list: list, metrics: metrics)
        }
      } else {
        PamnotSingleBoxView(payload: payload, list: list, box: entry.box, family: family, metrics: metrics)
      }
    } else {
      PamnotListPlaceholderView()
    }
  }
}

/// Small, all boxes: list name, the first three open tasks in matrix order, "+N" for the rest.
struct PamnotAllSmallView: View {
  let payload: PamnotListsPayload
  let list: PamnotListSummary
  let metrics: PamnotListMetrics

  var body: some View {
    let shown = Array(list.allItems.prefix(3))
    VStack(alignment: .leading, spacing: 4) {
      PamnotListHeader(title: list.name, count: nil, size: metrics.titleSize)
      PamnotTaskRows(items: shown, emptyText: payload.emptyText, metrics: metrics)
      PamnotMoreText(count: list.totalCount - shown.count, size: metrics.headerSize)
      Spacer(minLength: 0)
    }
  }
}

/// Medium, all boxes: two columns (Important · Urgent and Important · Planned), three each.
struct PamnotAllMediumView: View {
  let payload: PamnotListsPayload
  let list: PamnotListSummary
  let metrics: PamnotListMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      PamnotListHeader(title: list.name, count: nil, size: metrics.titleSize)
      HStack(alignment: .top, spacing: 12) {
        PamnotBoxColumn(payload: payload, list: list, box: .doNow, limit: 3, metrics: metrics)
        PamnotBoxColumn(payload: payload, list: list, box: .plan, limit: 3, metrics: metrics)
      }
      Spacer(minLength: 0)
    }
  }
}

/// Large, all boxes: a 2×2 matrix, three tasks per box.
struct PamnotAllLargeView: View {
  let payload: PamnotListsPayload
  let list: PamnotListSummary
  let metrics: PamnotListMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      PamnotListHeader(title: list.name, count: list.totalCount, size: metrics.titleSize)
      HStack(alignment: .top, spacing: 12) {
        PamnotBoxColumn(payload: payload, list: list, box: .doNow, limit: 3, metrics: metrics)
        PamnotBoxColumn(payload: payload, list: list, box: .plan, limit: 3, metrics: metrics)
      }
      Divider()
      HStack(alignment: .top, spacing: 12) {
        PamnotBoxColumn(payload: payload, list: list, box: .delegate, limit: 3, metrics: metrics)
        PamnotBoxColumn(payload: payload, list: list, box: .later, limit: 3, metrics: metrics)
      }
      Spacer(minLength: 0)
    }
  }
}

/// One box: small 3 tasks, medium 6 in two columns, large 6; the title is the box name.
struct PamnotSingleBoxView: View {
  let payload: PamnotListsPayload
  let list: PamnotListSummary
  let box: PamnotBoxChoice
  let family: WidgetFamily
  let metrics: PamnotListMetrics

  var body: some View {
    let summary = list.box(box)
    let limit = family == .systemSmall ? 3 : 6
    let shown = Array(summary.items.prefix(limit))
    VStack(alignment: .leading, spacing: 4) {
      PamnotListHeader(title: payload.title(of: box), count: summary.count, size: metrics.titleSize)
      Text(list.name)
        .font(.system(size: metrics.headerSize, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      if family == .systemMedium && shown.count > 3 {
        HStack(alignment: .top, spacing: 12) {
          PamnotTaskRows(items: Array(shown.prefix(3)), emptyText: payload.emptyText, metrics: metrics)
          PamnotTaskRows(items: Array(shown.dropFirst(3)), emptyText: payload.emptyText, metrics: metrics)
        }
      } else {
        PamnotTaskRows(items: shown, emptyText: payload.emptyText, metrics: metrics)
      }
      if family == .systemSmall {
        PamnotMoreText(count: summary.count - shown.count, size: metrics.headerSize)
      }
      Spacer(minLength: 0)
    }
  }
}

/// A box title with its open-task count, then up to [limit] rows.
struct PamnotBoxColumn: View {
  let payload: PamnotListsPayload
  let list: PamnotListSummary
  let box: PamnotBoxChoice
  let limit: Int
  let metrics: PamnotListMetrics

  var body: some View {
    let summary = list.box(box)
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Text(payload.title(of: box))
          .font(.system(size: metrics.headerSize, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 2)
        if summary.count > 0 {
          Text(verbatim: "\(summary.count)")
            .font(.system(size: metrics.headerSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)
      PamnotTaskRows(items: Array(summary.items.prefix(limit)), emptyText: payload.emptyText, metrics: metrics)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

struct PamnotListHeader: View {
  let title: String
  let count: Int?
  let size: CGFloat

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(title)
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .widgetAccentable()
      Spacer(minLength: 2)
      if let count, count > 0 {
        Text(verbatim: "\(count)")
          .font(.system(size: size - 2, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// The rows, or the "no tasks" text when there are none.
struct PamnotTaskRows: View {
  let items: [PamnotListItem]
  let emptyText: String
  let metrics: PamnotListMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if items.isEmpty {
        Text(emptyText)
          .font(.system(size: metrics.rowSize - 1, design: .rounded))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .frame(minHeight: metrics.rowHeight, alignment: .leading)
      } else {
        ForEach(items) { item in
          PamnotTaskRow(item: item, metrics: metrics)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

/// Tapping the row (circle, title, time) finishes the task without opening the app.
struct PamnotTaskRow: View {
  let item: PamnotListItem
  let metrics: PamnotListMetrics

  var body: some View {
    Button(intent: PamnotCompleteTaskIntent(taskId: item.id)) {
      HStack(spacing: 6) {
        Image(systemName: "circle")
          .font(.system(size: metrics.rowSize, weight: .medium))
          .foregroundStyle(.secondary)
        Text(item.title)
          .font(.system(size: metrics.rowSize, design: .rounded))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 2)
        if !item.time.isEmpty {
          Text(item.time)
            .font(.system(size: metrics.rowSize - 2, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .layoutPriority(1)
        }
      }
      .frame(maxWidth: .infinity, minHeight: metrics.rowHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(item.title))
    .accessibilityHint(Text("Marks the task as done"))
  }
}

struct PamnotMoreText: View {
  let count: Int
  let size: CGFloat

  var body: some View {
    if count > 0 {
      Text(verbatim: "+\(count)")
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }
}

/// No (readable) data yet: the Pamnot glyph and "Open Pamnot".
struct PamnotListPlaceholderView: View {
  var body: some View {
    VStack(spacing: 6) {
      PamnotGlyph(color: PamnotPalette.lavender, size: 28)
        .accessibilityHidden(true)
      Text(verbatim: "Pamnot")
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
      Text("Open Pamnot")
        .font(.system(size: 12, design: .rounded))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Previews

#if DEBUG
struct PamnotListWidget_Previews: PreviewProvider {
  static let entry = PamnotListEntry(date: Date(), payload: .sample(turkish: true), listId: nil, box: .all)
  static let single = PamnotListEntry(date: Date(), payload: .sample(turkish: true), listId: nil, box: .plan)
  static let empty = PamnotListEntry(date: Date(), payload: nil, listId: nil, box: .all)

  static var previews: some View {
    Group {
      PamnotListWidgetView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemSmall))
      PamnotListWidgetView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemMedium))
      PamnotListWidgetView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemLarge))
      PamnotListWidgetView(entry: single)
        .previewContext(WidgetPreviewContext(family: .systemMedium))
      PamnotListWidgetView(entry: empty)
        .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
  }
}
#endif
