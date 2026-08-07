import WidgetKit
import SwiftUI

// Registers the Live Activity widget extension entry.
@main
struct CodexNotchLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        CodexTaskLiveActivityWidget()
    }
}
