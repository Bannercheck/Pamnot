import SwiftUI
import WidgetKit

/// Entry point of the PamukWidget extension.
@main
struct PamukWidgetBundle: WidgetBundle {
  var body: some Widget {
    PamukTodayWidget()
  }
}
