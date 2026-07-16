package com.healthmd.rawexport

import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_ALLERGIES_INTOLERANCES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_CONDITIONS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_LABORATORY_RESULTS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_MEDICATIONS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PERSONAL_DETAILS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PRACTITIONER_DETAILS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PREGNANCY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PROCEDURES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_SOCIAL_HISTORY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VACCINES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VISITS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VITAL_SIGNS
import androidx.health.connect.client.records.MedicalResource

internal data class RawTypeDefinition(
    val typeKey: String,
    val wireType: String,
    val permission: String,
    val feature: String?,
    val rangeBehavior: RawRangeBehavior,
    val metricIds: Set<String>,
)

internal data class RawMedicalTypeDescriptor(
    val type: Int,
    val typeKey: String,
    val permission: String,
)

/** Closed v1 report inventory: 42 ordinary records and 12 PHR categories. */
@OptIn(ExperimentalPersonalHealthRecordApi::class)
internal object RawExportTypeCatalog {
    const val MEDICAL_METRIC_ID = "medical_resources"
    const val PHR_FEATURE_NAME = "personal_health_record"

    val medicalTypes: List<RawMedicalTypeDescriptor> = listOf(
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_VACCINES, "medical_resource/vaccines", PERMISSION_READ_MEDICAL_DATA_VACCINES),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_ALLERGIES_INTOLERANCES, "medical_resource/allergies_intolerances", PERMISSION_READ_MEDICAL_DATA_ALLERGIES_INTOLERANCES),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_PREGNANCY, "medical_resource/pregnancy", PERMISSION_READ_MEDICAL_DATA_PREGNANCY),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_SOCIAL_HISTORY, "medical_resource/social_history", PERMISSION_READ_MEDICAL_DATA_SOCIAL_HISTORY),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_VITAL_SIGNS, "medical_resource/vital_signs", PERMISSION_READ_MEDICAL_DATA_VITAL_SIGNS),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_LABORATORY_RESULTS, "medical_resource/laboratory_results", PERMISSION_READ_MEDICAL_DATA_LABORATORY_RESULTS),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_CONDITIONS, "medical_resource/conditions", PERMISSION_READ_MEDICAL_DATA_CONDITIONS),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_PROCEDURES, "medical_resource/procedures", PERMISSION_READ_MEDICAL_DATA_PROCEDURES),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_MEDICATIONS, "medical_resource/medications", PERMISSION_READ_MEDICAL_DATA_MEDICATIONS),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_PERSONAL_DETAILS, "medical_resource/personal_details", PERMISSION_READ_MEDICAL_DATA_PERSONAL_DETAILS),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_PRACTITIONER_DETAILS, "medical_resource/practitioner_details", PERMISSION_READ_MEDICAL_DATA_PRACTITIONER_DETAILS),
        RawMedicalTypeDescriptor(MedicalResource.MEDICAL_RESOURCE_TYPE_VISITS, "medical_resource/visits", PERMISSION_READ_MEDICAL_DATA_VISITS),
    ).sortedBy { it.type }

    val definitions: List<RawTypeDefinition> =
        HealthConnectRecordCatalog.records.map { descriptor ->
            RawTypeDefinition(
                typeKey = descriptor.wireType,
                wireType = descriptor.wireType,
                permission = descriptor.readPermission,
                feature = descriptor.featureName,
                rangeBehavior = descriptor.rangeBehavior,
                metricIds = descriptor.metricIds,
            )
        } + medicalTypes.map { descriptor ->
            RawTypeDefinition(
                typeKey = descriptor.typeKey,
                wireType = "medical_resource",
                permission = descriptor.permission,
                feature = PHR_FEATURE_NAME,
                rangeBehavior = RawRangeBehavior.UNBOUNDED_NON_TEMPORAL,
                metricIds = setOf(MEDICAL_METRIC_ID),
            )
        }

    val byKey: Map<String, RawTypeDefinition> = definitions.associateBy { it.typeKey }
    private val issueOrder: Map<String, Int> = definitions.mapIndexed { index, definition -> definition.typeKey to index }.toMap()

    fun isSelected(definition: RawTypeDefinition, request: RawSnapshotRequest): Boolean =
        request.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA ||
            definition.metricIds.any(request.selectedMetricIds::contains)

    fun issueRank(recordType: String?): Int = when {
        recordType == null -> -1
        recordType == "medical_resource" -> HealthConnectRecordCatalog.records.size
        else -> issueOrder[recordType] ?: Int.MAX_VALUE
    }

}
