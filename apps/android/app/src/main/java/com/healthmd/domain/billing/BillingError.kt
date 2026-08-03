package com.healthmd.domain.billing

/** Typed billing failures that presentation resolves in the current app locale. */
enum class BillingError {
    PRODUCT_UNAVAILABLE,
    SERVICE_UNAVAILABLE,
    PURCHASE_FAILED,
    NO_PREVIOUS_PURCHASE,
    RESTORE_FAILED,
}
