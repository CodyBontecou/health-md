import com.healthmd.accountsync.ProfileSyncV1
import com.healthmd.accountsync.ProfileSyncV1FixtureConformance
import com.healthmd.sharedsetup.SharedSetupMetricRegistry
import com.healthmd.sharedsetup.SharedSetupRegistryBinding
import com.healthmd.sharedsetup.SharedSetupV2Codec
import java.io.File
import kotlinx.serialization.json.*

fun main(args: Array<String>) {
    require(args.size == 1) { "Pass this checkout's repository root" }
    val root = File(args[0])
    val evidence = Json.parseToJsonElement(File(root, "packages/contracts/profile-sync/v1/registry-evidence.json").readText()).jsonObject
    val registry = object : SharedSetupMetricRegistry {
        override val version = 1
        override val sha256 = evidence.getValue("sha256").jsonPrimitive.content
        override val bySemanticId = evidence.getValue("aliases").jsonObject.mapValues { (id, raw) ->
            val row = raw.jsonArray
            SharedSetupRegistryBinding(id, row[1].jsonPrimitive.contentOrNull, row[2].jsonPrimitive.contentOrNull, row[0].jsonPrimitive.content)
        }
        override val byAndroidSelectionId = bySemanticId.values.mapNotNull { v -> v.androidSelectionId?.let { it to v } }.toMap()
    }
    val result = ProfileSyncV1FixtureConformance.run(root, ProfileSyncV1(SharedSetupV2Codec(registry)))
    println("Kotlin real v2 + profile-sync codecs: $result")
    println("Injected byte-pinned host registry, not core/Android adapter; no auth/storage/native apply/UI/physical qualification")
}
