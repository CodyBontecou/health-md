import com.healthmd.data.receivercoverage.*
import java.nio.file.Files
import java.time.Instant
import java.util.Base64
import java.io.File
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
private fun hex(s:String)=s.chunked(2).map{it.toInt(16).toByte()}.toByteArray()
private fun evidence(request:ReceiverCoverageRequest,days:List<String>):ReceiverCoverageOutcome {
    val fields=Json.parseToJsonElement(request.body().toString(Charsets.UTF_8)).jsonObject.toMutableMap()
    fields["schema"]=JsonPrimitive("healthmd.receiver_coverage.response"); fields["completed_dates"]=JsonArray(days.map(::JsonPrimitive))
    return ReceiverCoverageOutcome.Valid(ReceiverCoverageEvidence.parse(JsonObject(fields).toString().toByteArray(),request))
}
fun main(args:Array<String>)=runBlocking {
    val preflight=/*PREPARE*/!!
    for(line in File(args[0]).readLines()) {
        val p=line.split('\t'); val text=String(Base64.getDecoder().decode(p[2]),Charsets.UTF_8)
        try {val plan=ReceiverCoveragePlan.restore(text,"a".repeat(64)); check(p[1]=="valid"); println(p[0]+"\t"+Base64.getEncoder().encodeToString(plan.json().toByteArray()))}
        catch(e:Exception){check(p[1]=="invalid"){"Rejected valid plan ${p[0]}: $e"}; println(p[0]+"\tinvalid")}
    }
    val directory=Files.createTempDirectory("healthmd-170-plan-")
    try {
        val journal=ReceiverCoverageJournal(directory); var calls=0
        val now=Instant.parse("2026-03-09T08:00:00Z"); val candidates=listOf("2026-03-06","2026-03-07","2026-03-08")
        val plan=journal.resolve("occurrence","profile:g1:fire1",preflight,candidates,now,true,{true}) {calls++; evidence(it,listOf("2026-03-06","2026-03-08"))}
        check(plan.selected==listOf("2026-03-07","2026-03-08","2026-03-09"))
        journal.acknowledge("occurrence","profile:g1:fire1",preflight.destinationBinding,listOf("2026-03-07","2026-03-09"))
        val restarted=ReceiverCoverageJournal(directory)
        val retry=restarted.resolve("occurrence","profile:g1:fire1",preflight,listOf("2050-01-01"),now.plusSeconds(864000),false,{true}){error("Retry queried receiver")}
        check(retry.residual==listOf("2026-03-08") && retry.today=="2026-03-09")
        val path=directory.resolve("occurrence.json"); val saved=Files.readAllBytes(path)
        try{restarted.restore("occurrence","changed",preflight.destinationBinding); error("Changed authority restored")}catch(e:IllegalArgumentException){}
        try{restarted.restore("occurrence","profile:g1:fire1","b".repeat(64)); error("Changed binding restored")}catch(e:ReceiverCoveragePreflight.BoundaryException){}
        try{restarted.acknowledge("occurrence","profile:g1:fire1",preflight.destinationBinding,listOf("2026-03-06")); error("Unselected ack accepted")}catch(e:ReceiverCoveragePreflight.BoundaryException){}
        check(Files.readAllBytes(path).contentEquals(saved))
        try{journal.resolve("cancelled","g1",preflight,candidates,now,false,{true}){calls++; throw CancellationException()}; error("Cancellation swallowed")}catch(e:CancellationException){}
        val recovered=restarted.resolve("cancelled","g1",preflight,emptyList(),now,false,{true}){error("Crashed preflight repeated")}
        check(recovered.residual==candidates && recovered.status=="fallback_full")
        val emptyPreflight=ReceiverCoveragePreflight.prepare(ReceiverCoveragePreflight.Policy.MISSING_DAYS,preflight.uploadUrl.toString(),preflight.preflightUrl.toString(),mapOf("Authorization" to "Bearer synthetic","X-Tenant" to "synthetic"),preflight.scopeId,preflight.calendarTimezone,"{\"profile\":\"synthetic\"}".toByteArray(),0,ByteArray(32){1})!!
        val empty=journal.resolve("empty","g1",emptyPreflight,candidates,now,false,{true}){evidence(it,candidates)}
        check(empty.selected.isEmpty() && empty.residual.isEmpty())
        val emptyRetry=restarted.resolve("empty","g1",emptyPreflight,emptyList(),now,true,{true}){error("Empty plan reselected")}
        check(emptyRetry.residual.isEmpty())
        val bad=directory.resolve("file"); Files.write(bad,byteArrayOf(1))
        try{ReceiverCoverageJournal(bad).resolve("blocked","g1",preflight,candidates,now,false,{true}){error("HTTP before durable admission")}; error("Write failure ignored")}catch(e:java.io.IOException){}
        check(calls==2)
    } finally {directory.toFile().deleteRecursively()}
    println("transport\tok")
}
