import com.healthmd.data.scheduler.ScheduledExportPendingRequests as Pending
import com.healthmd.domain.model.*
import java.time.LocalDate
fun main(){
 val a=LocalDate.parse("2026-03-06"); val b=a.plusDays(1)
 val initial=ExportSettings()
 val accepted=Pending.applyCancellationResult(initial,listOf(a,b),listOf(a,b),target=ExportTarget.API_ENDPOINT,destinationFingerprint="original",settingsSnapshotJson="original-settings",receiverPlanId="original-plan")
 check(accepted.pendingScheduledExportRequests.all{it.receiverPlanId=="original-plan" && it.apiOperationId==null && it.attemptCount==0})
 val partial=Pending.applyAttemptResult(accepted,listOf(a,b),listOf(FailedDateDetail(b)),target=ExportTarget.API_ENDPOINT,destinationFingerprint="original",settingsSnapshotJson="edited-settings",apiOperationIds=mapOf(b to "prepared-body"),receiverPlanId="replacement-plan")
 check(partial.pendingScheduledExportRequests.single().let{it.date==b && it.receiverPlanId=="original-plan" && it.settingsSnapshotJson=="original-settings" && it.apiOperationId=="prepared-body"})
 val fresh=Pending.applyAttemptResult(partial,listOf(b),listOf(FailedDateDetail(b)),target=ExportTarget.API_ENDPOINT,destinationFingerprint="original",freshCaptureRetryDates=setOf(b))
 check(fresh.pendingScheduledExportRequests.single().let{it.receiverPlanId=="original-plan" && it.apiOperationId==null})
 val unrelated=Pending.applyAttemptResult(fresh,listOf(a),listOf(FailedDateDetail(a)),target=ExportTarget.DEVICE_FOLDER)
 val empty=Pending.applyAttemptResult(unrelated,listOf(b),emptyList(),target=ExportTarget.API_ENDPOINT,destinationFingerprint="original")
 check(empty.pendingScheduledExportRequests.single().exportTarget==ExportTarget.DEVICE_FOLDER)
 val changed=Pending.applyAttemptResult(fresh,listOf(b),emptyList(),target=ExportTarget.API_ENDPOINT,destinationFingerprint="changed")
 check(changed.pendingScheduledExportRequests.single().receiverPlanId=="original-plan")
 val config=com.healthmd.data.receivercoverage.ReceiverCoverageConfiguration("https://example.com/coverage","scope-1",1)
 val protected=com.healthmd.data.receivercoverage.ReceiverCoverageSnapshot.wrap("{\"version\":2}",config.json(),"original-plan","a".repeat(64),"b".repeat(64))
 val protectedSettings=ExportSettings(pendingScheduledExportRequests=listOf(PendingScheduledExportRequest(b,exportTarget=ExportTarget.API_ENDPOINT,destinationFingerprint="original",settingsSnapshotJson=protected)))
 check(Pending.pendingRequests(protectedSettings).single().receiverPlanId=="original-plan")
 check(com.healthmd.data.receivercoverage.ReceiverCoverageSnapshot.outputSettings(protected)=="{\"version\":2}")
 val future=protected.replace("\"schema_version\":1","\"schema_version\":2")
 try {com.healthmd.data.receivercoverage.ReceiverCoverageSnapshot.authority(future); error("Future authority accepted")}
 catch(e:com.healthmd.data.receivercoverage.ReceiverCoveragePreflight.BoundaryException){}
 println("Real Android pending model/helper: plan identity, partial acknowledgement, fresh detach, unrelated retention, destination change passed")
}
