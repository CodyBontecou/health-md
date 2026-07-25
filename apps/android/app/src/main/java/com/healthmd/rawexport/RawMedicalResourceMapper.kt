package com.healthmd.rawexport

import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.records.FhirResource
import androidx.health.connect.client.records.MedicalDataSource
import androidx.health.connect.client.records.MedicalResource
import kotlinx.serialization.json.*

@OptIn(ExperimentalPersonalHealthRecordApi::class)
object RawMedicalResourceMapper {
    fun map(resource: MedicalResource, source: MedicalDataSource?): RawRecord {
        val resourceIdentity = listOf(
            resource.id.dataSourceId,
            resource.id.fhirResourceType.toString(),
            resource.id.fhirResourceId,
        ).joinToString(":")
        val fields = buildJsonObject {
            put("medicalResourceType", enum(resource.type, medicalTypeLabel(resource.type)))
            put("medicalResourceId", buildJsonObject {
                put("dataSourceId", resource.id.dataSourceId)
                put("fhirResourceType", enum(resource.id.fhirResourceType, fhirTypeLabel(resource.id.fhirResourceType)))
                put("fhirResourceId", resource.id.fhirResourceId)
            })
            put("dataSourceId", resource.dataSourceId)
            put("fhirVersion", buildJsonObject {
                put("major", resource.fhirVersion.major)
                put("minor", resource.fhirVersion.minor)
                put("patch", resource.fhirVersion.patch)
            })
            put("fhirResource", buildJsonObject {
                put("type", enum(resource.fhirResource.type, fhirTypeLabel(resource.fhirResource.type)))
                put("id", resource.fhirResource.id)
                put("fhirResourceJson", resource.fhirResource.data)
                put("checksumSha256", RawJson.sha256(resource.fhirResource.data.toByteArray(Charsets.UTF_8)))
            })
            put("source", source?.let { dataSource -> buildJsonObject {
                put("id", dataSource.id)
                put("packageName", dataSource.packageName)
                put("fhirBaseUri", dataSource.fhirBaseUri.toString())
                put("displayName", dataSource.displayName)
                put("fhirVersion", buildJsonObject {
                    put("major", dataSource.fhirVersion.major)
                    put("minor", dataSource.fhirVersion.minor)
                    put("patch", dataSource.fhirVersion.patch)
                })
                put("lastDataUpdateTime", dataSource.lastDataUpdateTime?.let {
                    RawJson.codec.encodeToJsonElement(RawInstant.serializer(), RawInstant(it.epochSecond, it.nano))
                } ?: JsonNull)
            }} ?: JsonNull)
        }
        return RawRecord(
            wireType = "medical_resource",
            nativeIdentity = "medical:$resourceIdentity",
            fields = fields,
            hash = "",
        ).withCanonicalIdentityAndHash()
    }

    private fun enum(raw: Int, label: String): JsonElement =
        RawJson.codec.encodeToJsonElement(RawEnumValue.serializer(), RawEnumValue(raw, label))

    private fun medicalTypeLabel(v: Int) = mapOf(
        1 to "vaccines", 2 to "allergies_intolerances", 3 to "pregnancy",
        4 to "social_history", 5 to "vital_signs", 6 to "laboratory_results",
        7 to "conditions", 8 to "procedures", 9 to "medications",
        10 to "personal_details", 11 to "practitioner_details", 12 to "visits",
    )[v] ?: "unknown_$v"

    private fun fhirTypeLabel(v: Int) = mapOf(
        FhirResource.FHIR_RESOURCE_TYPE_IMMUNIZATION to "immunization",
        FhirResource.FHIR_RESOURCE_TYPE_ALLERGY_INTOLERANCE to "allergy_intolerance",
        FhirResource.FHIR_RESOURCE_TYPE_OBSERVATION to "observation",
        FhirResource.FHIR_RESOURCE_TYPE_CONDITION to "condition",
        FhirResource.FHIR_RESOURCE_TYPE_PROCEDURE to "procedure",
        FhirResource.FHIR_RESOURCE_TYPE_MEDICATION to "medication",
        FhirResource.FHIR_RESOURCE_TYPE_MEDICATION_REQUEST to "medication_request",
        FhirResource.FHIR_RESOURCE_TYPE_MEDICATION_STATEMENT to "medication_statement",
        FhirResource.FHIR_RESOURCE_TYPE_PATIENT to "patient",
        FhirResource.FHIR_RESOURCE_TYPE_PRACTITIONER to "practitioner",
        FhirResource.FHIR_RESOURCE_TYPE_PRACTITIONER_ROLE to "practitioner_role",
        FhirResource.FHIR_RESOURCE_TYPE_ENCOUNTER to "encounter",
        FhirResource.FHIR_RESOURCE_TYPE_LOCATION to "location",
        FhirResource.FHIR_RESOURCE_TYPE_ORGANIZATION to "organization",
    )[v] ?: "unknown_$v"
}
