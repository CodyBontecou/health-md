import SwiftUI
import WidgetKit

@main
struct HealthMdWidgetBundle: WidgetBundle {
    var body: some Widget {
        HealthSummaryWidget()
        ActivityRingsWidget()
        HeartRangeWidget()
        SleepSummaryWidget()
    }
}
