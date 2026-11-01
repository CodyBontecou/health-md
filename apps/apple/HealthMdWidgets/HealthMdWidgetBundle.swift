import SwiftUI
import WidgetKit

@main
struct HealthMdWidgetBundle: WidgetBundle {
    var body: some Widget {
        HealthSummaryWidget()
        ActivityRingsWidget()
        HeartRangeWidget()
        SleepSummaryWidget()
        CLIExportLiveActivityWidget()
        #if NEW_EXPERIENCE_WIDGETS
        ArchiveWidget()
        #endif
    }
}
