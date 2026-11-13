import android.content.Context
import com.healthmd.data.export.*
import com.healthmd.data.scheduler.ReceiverCoverageRuntime
import com.healthmd.data.receivercoverage.*
import com.healthmd.domain.repository.EntitlementRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.serialization.json.*
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
private class Credentials:APIExportCredentialStore {
 var key:ByteArray?=null
 var authorization="Bearer synthetic"
 override suspend fun receiverCoverageKey(create:Boolean):ByteArray {
  if(key==null){check(create){"Missing recovery key"}; key=ByteArray(32){1}}
  return requireNotNull(key).copyOf()
 }
 override suspend fun requestConfiguration(endpoint:String)=APIExportRequestConfiguration(endpoint,authorization,emptyList(),"b".repeat(64))
}
private class Entitlements:EntitlementRepository {
 override val sponsoredEndpoint=MutableStateFlow<String?>(null)
 override suspend fun verifyAccess()=true
 override suspend fun clinicUploadAuthorization(endpoint:String):String?=null
}
fun main()=runBlocking {
 val root=Files.createTempDirectory("healthmd-170-runtime-")
 try {
  val context=Context(root.toFile()); val credentials=Credentials(); val access=Entitlements()
  val config=ReceiverCoverageConfiguration("https://example.com/coverage","scope-1",1)
  ReceiverCoverageRuntime.save(context,"legacy",config,"https://example.com/upload",credentials)
  val runtime=ReceiverCoverageRuntime(context,credentials,access)
  val frozen=runtime.configurationForOccurrence("occurrence","legacy",true)
  check(frozen==config.json())
  val changed=ReceiverCoverageConfiguration("https://example.com/new-coverage","scope-2",0)
  ReceiverCoverageRuntime.save(context,"legacy",changed,"https://example.com/upload",credentials)
  check(runtime.configurationForOccurrence("occurrence","legacy",true)==config.json())
  check(runtime.configurationForOccurrence("next-occurrence","legacy",true)==changed.json())
  val unbound="{\"version\":2,\"settings\":\"original\"}"
  try {runtime.destination(config.json(),"https://example.com/upload",unbound,"UTC"); error("Unbound source accepted")}
  catch(e:IllegalArgumentException){}
  val output="{\"version\":5,\"settings\":\"original\",\"providerCaptureAuthority\":{\"selectedProviderId\":\"whoop\",\"connectionIds\":{\"whoop\":\"11111111-1111-4111-8111-111111111111\"}}}"
  val destination=runtime.destination(config.json(),"https://example.com/upload",output,"UTC")
  try {runtime.destination(config.json(),"https://example.com/upload",output.replace("original","edited"),"UTC"); error("Scope reused after output edit")}
  catch(e:IllegalStateException){}
  try {runtime.destination(config.json(),"https://example.com/upload",output.replace("11111111-1111-4111-8111-111111111111","22222222-2222-4222-8222-222222222222"),"UTC"); error("Scope reused after provider account change")}
  catch(e:IllegalStateException){}
  val journal=ReceiverCoverageJournal(root.resolve("receiver-coverage/plans"))
  val now=Instant.parse("2026-03-09T08:00:00Z"); val dates=listOf("2026-03-06","2026-03-07","2026-03-08")
  val accepted=journal.resolve("occurrence","legacy:occurrence",destination.preflight,dates,now,false,{true}) { request ->
   val o=Json.parseToJsonElement(request.body().toString(Charsets.UTF_8)).jsonObject.toMutableMap()
   o["schema"]=JsonPrimitive("healthmd.receiver_coverage.response"); o["completed_dates"]=JsonArray(listOf(JsonPrimitive("2026-03-06")))
   ReceiverCoverageOutcome.Valid(ReceiverCoverageEvidence.parse(JsonObject(o).toString().toByteArray(),request))
  }
  check(accepted.selected==listOf("2026-03-07","2026-03-08"))
  val restarted=ReceiverCoverageRuntime(context,credentials,access)
  val lease=restarted.resolve("occurrence","legacy:occurrence",config.json(),"https://example.com/upload",output,"UTC",emptyList(),false,now.plusSeconds(864000),restoreOnly=true,authorized={true})
  check(lease.plan.residual==accepted.selected)
  runtime.acknowledge(lease,listOf(LocalDate.parse("2026-03-07")))
  val partial=restarted.resolve("occurrence","legacy:occurrence",config.json(),"https://example.com/upload",output,"UTC",emptyList(),false,now,restoreOnly=true,authorized={true})
  check(partial.plan.residual==listOf("2026-03-08"))
  legacyReceiverBoundary(context,credentials,access,output)
  val path=root.resolve("receiver-coverage/plans/occurrence.json"); val bytes=Files.readAllBytes(path)
  credentials.authorization="Bearer different-account"
  try {restarted.resolve("occurrence","legacy:occurrence",config.json(),"https://example.com/upload",output,"UTC",emptyList(),false,now,restoreOnly=true,authorized={true}); error("Destination silently changed")}
  catch(e:ReceiverCoveragePreflight.BoundaryException){}
  check(Files.readAllBytes(path).contentEquals(bytes))
  credentials.authorization="Bearer synthetic"; credentials.key=null
  try {ReceiverCoverageRuntime.save(context,"legacy",config,"https://example.com/upload",credentials); error("Lost recovery key rotated")}
  catch(e:IllegalStateException){}
  check(credentials.key==null)
  // An unlistable plan location must not authorize creation of a replacement key.
  val plans=root.resolve("receiver-coverage/plans")
  plans.toFile().deleteRecursively()
  val obstruction="preserve-unknown-state".toByteArray()
  Files.write(plans,obstruction)
  val originalConfiguration=ReceiverCoverageRuntime.configuration(context,"legacy")
  val blocked=runCatching {ReceiverCoverageRuntime.save(context,"legacy",config,"https://example.com/upload",credentials)}.isFailure
  check(blocked){"Unlistable recovery state allowed a replacement key"}
  check(credentials.key==null)
  check(Files.readAllBytes(plans).contentEquals(obstruction))
  check(ReceiverCoverageRuntime.configuration(context,"legacy")==originalConfiguration)
  Files.delete(plans)
  credentials.key=ByteArray(32){1}; access.sponsoredEndpoint.value="https://example.com/upload"
  try {runtime.destination(config.json(),"https://example.com/upload",output,"UTC"); error("Managed rotating destination accepted")}
  catch(e:IllegalStateException){}
 } finally {root.toFile().deleteRecursively()}
 println("Actual Android runtime: frozen configuration, scope binding, restart, partial ack, credential changes, missing keys passed")
}
