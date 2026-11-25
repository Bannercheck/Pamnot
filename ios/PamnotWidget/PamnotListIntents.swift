import AppIntents
import Foundation
import WidgetKit

// The list widget's configuration (which list, which box) and the "done" button's intent.
// Every title here is an English key looked up in this extension's Localizable.strings (en / tr).

// MARK: - List entity

/// One of the user's lists, as written by the app under `pamnot_lists`.
struct PamnotListEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "List"
  static var defaultQuery = PamnotListQuery()

  let id: String
  let name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

/// Reads the lists from the App Group JSON; the first list is the default.
struct PamnotListQuery: EntityQuery {
  func entities(for identifiers: [PamnotListEntity.ID]) async throws -> [PamnotListEntity] {
    let all = Self.allEntities()
    return identifiers.compactMap { id in all.first { $0.id == id } }
  }

  func suggestedEntities() async throws -> [PamnotListEntity] {
    Self.allEntities()
  }

  func defaultResult() async -> PamnotListEntity? {
    Self.allEntities().first
  }

  static func allEntities() -> [PamnotListEntity] {
    (PamnotListStore.load()?.lists ?? []).map { PamnotListEntity(id: $0.id, name: $0.name) }
  }
}

// MARK: - Box choice

/// "All" or one of the four boxes; the raw values are the box keys in the JSON.
enum PamnotBoxChoice: String, AppEnum {
  case all, doNow, plan, delegate, later

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Box"
  static var caseDisplayRepresentations: [PamnotBoxChoice: DisplayRepresentation] = [
    .all: "All",
    .doNow: "Important · Urgent",
    .plan: "Important · Planned",
    .delegate: "Urgent · Less important",
    .later: "Later · Maybe",
  ]

  /// The four boxes in matrix order.
  static let boxes: [PamnotBoxChoice] = [.doNow, .plan, .delegate, .later]

  /// Title from this extension's strings, for when the app's JSON carries none.
  var fallbackTitle: String {
    switch self {
    case .all: return String(localized: "All")
    case .doNow: return String(localized: "Important · Urgent")
    case .plan: return String(localized: "Important · Planned")
    case .delegate: return String(localized: "Urgent · Less important")
    case .later: return String(localized: "Later · Maybe")
    }
  }
}

// MARK: - Configuration

struct PamnotListConfigIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Choose List"
  static var description = IntentDescription("Choose the list and box the widget shows.")

  @Parameter(title: "List")
  var list: PamnotListEntity?

  @Parameter(title: "Box", default: .all)
  var box: PamnotBoxChoice
}

// MARK: - Done button

/// Ticks a task on the widget without opening the app. The id is queued under
/// `pamnot_pending_done` (the app finishes it on its next start or resume) and the task is
/// taken out of `pamnot_lists` at once, so the widget is up to date before the app runs.
struct PamnotCompleteTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete Task"
  static var openAppWhenRun: Bool = false
  static var isDiscoverable: Bool = false

  @Parameter(title: "Task")
  var taskId: String

  init() {}

  init(taskId: String) {
    self.taskId = taskId
  }

  func perform() async throws -> some IntentResult {
    PamnotListStore.complete(taskId: taskId)
    WidgetCenter.shared.reloadTimelines(ofKind: PamnotShared.listWidgetKind)
    return .result()
  }
}

// MARK: - Writing to the App Group

extension PamnotListStore {
  /// Adds [taskId] to the pending list (once) and removes the task from the stored summary,
  /// lowering its box's `count` by one. Unknown fields in the JSON are kept as they are.
  static func complete(taskId: String) {
    let id = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, let defaults = UserDefaults(suiteName: PamnotShared.appGroupId) else { return }

    var pending = pendingIds(defaults.string(forKey: PamnotShared.pendingDoneKey))
    if !pending.contains(id) {
      pending.append(id)
      if let data = try? JSONSerialization.data(withJSONObject: pending),
         let text = String(data: data, encoding: .utf8) {
        defaults.set(text, forKey: PamnotShared.pendingDoneKey)
      }
    }

    if let raw = defaults.string(forKey: PamnotShared.listsKey),
       let updated = removing(taskId: id, from: raw) {
      defaults.set(updated, forKey: PamnotShared.listsKey)
    }
  }

  /// The string ids in the pending JSON array; anything unreadable counts as empty.
  static func pendingIds(_ text: String?) -> [String] {
    guard let data = text?.data(using: .utf8),
          let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
    else { return [] }
    return array.compactMap { $0 as? String }
  }

  /// The summary JSON without the task, or nil when the task is not in it.
  static func removing(taskId: String, from raw: String) -> String? {
    guard let data = raw.data(using: .utf8),
          var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          var lists = root["lists"] as? [[String: Any]]
    else { return nil }
    var found = false
    for l in lists.indices {
      guard var boxes = lists[l]["boxes"] as? [String: Any] else { continue }
      for (key, value) in boxes {
        guard var box = value as? [String: Any], let items = box["items"] as? [[String: Any]] else { continue }
        let kept = items.filter { ($0["id"] as? String) != taskId }
        guard kept.count != items.count else { continue }
        found = true
        box["items"] = kept
        let count = (box["count"] as? NSNumber)?.intValue ?? items.count
        box["count"] = max(0, count - (items.count - kept.count))
        boxes[key] = box
      }
      lists[l]["boxes"] = boxes
    }
    guard found else { return nil }
    root["lists"] = lists
    guard let out = try? JSONSerialization.data(withJSONObject: root) else { return nil }
    return String(data: out, encoding: .utf8)
  }
}
