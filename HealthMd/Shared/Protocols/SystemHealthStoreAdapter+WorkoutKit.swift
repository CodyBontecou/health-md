import Foundation
#if canImport(WorkoutKit)
import WorkoutKit
#endif

extension SystemHealthStoreAdapter {
    var supportsScheduledWorkoutPlans: Bool {
        #if canImport(WorkoutKit) && !os(visionOS)
        if #available(iOS 17.0, macOS 15.0, macCatalyst 18.0, watchOS 10.0, *) {
            return WorkoutScheduler.isSupported
        }
        #endif
        return false
    }

    func queryScheduledWorkoutPlanRecords(
        interval: HealthKitQueryInterval,
        selectedMetricIDs: [String]
    ) async -> HealthKitScheduledWorkoutPlanQueryResult {
        #if canImport(WorkoutKit) && !os(visionOS)
        guard #available(iOS 17.0, macOS 15.0, macCatalyst 18.0, watchOS 10.0, *) else {
            return HealthKitScheduledWorkoutPlanQueryResult(
                status: .unsupported,
                statusDescription: "WorkoutKit scheduled-workout reads are unavailable on this OS version."
            )
        }
        guard WorkoutScheduler.isSupported else {
            return HealthKitScheduledWorkoutPlanQueryResult(
                status: .unsupported,
                statusDescription: "WorkoutScheduler.isSupported returned false on this device."
            )
        }

        let scheduler = WorkoutScheduler.shared
        switch await scheduler.authorizationState {
        case .authorized:
            break
        case .notDetermined:
            return HealthKitScheduledWorkoutPlanQueryResult(
                status: .skipped,
                statusDescription: "WorkoutKit schedule authorization is not determined. Export did not prompt or mutate the schedule."
            )
        case .restricted:
            return HealthKitScheduledWorkoutPlanQueryResult(
                status: .skipped,
                statusDescription: "WorkoutKit schedule access is restricted. Export did not prompt or mutate the schedule."
            )
        case .denied:
            return HealthKitScheduledWorkoutPlanQueryResult(
                status: .skipped,
                statusDescription: "WorkoutKit schedule access is denied. Export did not prompt or mutate the schedule."
            )
        @unknown default:
            return HealthKitScheduledWorkoutPlanQueryResult(
                status: .unsupported,
                statusDescription: "WorkoutKit returned an unknown schedule authorization state."
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = interval.calendarTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: 0)!
        var records: [HealthKitExternalRecord] = []
        var childResults: [HealthKitQueryResult] = []
        var warnings: [HealthKitRecordIntegrityWarning] = []

        for scheduled in await scheduler.scheduledWorkouts {
            let exactDateComponents = Self.dateComponentsValue(
                scheduled.date,
                fallbackCalendar: calendar
            )
            var resolvableComponents = scheduled.date
            if resolvableComponents.calendar == nil { resolvableComponents.calendar = calendar }
            if resolvableComponents.timeZone == nil { resolvableComponents.timeZone = calendar.timeZone }
            guard let scheduledDate = resolvableComponents.date else {
                warnings.append(HealthKitRecordIntegrityWarning(
                    code: "scheduled_workout_date_unresolvable",
                    message: "WorkoutKit returned schedule components that could not be assigned to a daily archive; the schedule was not leaked into an unrelated day.",
                    metricIDs: selectedMetricIDs
                ))
                continue
            }
            guard scheduledDate >= interval.startDate && scheduledDate < interval.endDate else {
                continue
            }

            do {
                let plan = try canonicalWorkoutPlanValue(scheduled.plan)
                records.append(HealthKitExternalRecordMapper.scheduledWorkoutPlan(
                    HealthKitScheduledWorkoutPlanValue(
                        plan: plan,
                        dateComponents: exactDateComponents,
                        complete: scheduled.complete
                    ),
                    objectTypeIdentifier: HealthKitRecordCatalog.scheduledWorkoutPlanIdentifier,
                    selectedMetricIDs: selectedMetricIDs
                ))
            } catch {
                childResults.append(HealthKitQueryResult(
                    identifier: "\(HealthKitRecordCatalog.scheduledWorkoutPlanIdentifier):\(scheduled.plan.id.uuidString)",
                    objectTypeIdentifier: HealthKitRecordCatalog.scheduledWorkoutPlanIdentifier,
                    operation: "serializeScheduledWorkoutPlan",
                    metricIDs: selectedMetricIDs,
                    metricAttribution: HealthKitMetricAttribution(directMetricIDs: selectedMetricIDs),
                    interval: interval,
                    status: .failure,
                    recordCount: 0,
                    error: HealthKitQueryError(error: error as NSError, isRecoverable: true),
                    statusDescription: "schedule_date_components_retained=true"
                ))
            }
        }

        return HealthKitScheduledWorkoutPlanQueryResult(
            externalRecords: records,
            status: childResults.isEmpty ? .success : .failure,
            statusDescription: childResults.isEmpty
                ? "Read WorkoutScheduler.scheduledWorkouts without requesting authorization or mutating the schedule."
                : "Some scheduled WorkoutPlan values could not provide their public dataRepresentation bytes.",
            childQueryResults: childResults,
            integrityWarnings: warnings
        )
        #else
        return HealthKitScheduledWorkoutPlanQueryResult(
            status: .unsupported,
            statusDescription: "WorkoutKit is unavailable to this app target/runtime."
        )
        #endif
    }
}
