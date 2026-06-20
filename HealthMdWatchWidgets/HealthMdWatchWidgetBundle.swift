import WidgetKit
import SwiftUI

@main
struct HealthMdWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyActivityWidget()
        RecoveryWidget()
    }
}
