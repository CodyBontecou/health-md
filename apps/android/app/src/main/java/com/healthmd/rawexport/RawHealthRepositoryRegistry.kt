package com.healthmd.rawexport

/** Truthful raw-provider dispatch. Unknown providers never fall back to Health Connect. */
class RawHealthRepositoryRegistry private constructor(
    private val repositories: Map<String, RawHealthRepository>,
) {
    fun repositoryFor(providerId: String): RawHealthRepository? = repositories[providerId]
    fun registeredProviderIds(): Set<String> = repositories.keys.toSortedSet()

    companion object {
        const val HEALTH_CONNECT = "health_connect"

        fun healthConnectOnly(repository: RawHealthRepository): RawHealthRepositoryRegistry =
            RawHealthRepositoryRegistry(mapOf(HEALTH_CONNECT to repository))

        fun withAdditionalRepositories(
            healthConnectRepository: RawHealthRepository,
            additionalRepositories: Map<String, RawHealthRepository>,
        ): RawHealthRepositoryRegistry = RawHealthRepositoryRegistry(
            buildMap {
                put(HEALTH_CONNECT, healthConnectRepository)
                putAll(additionalRepositories)
            },
        )
    }
}
