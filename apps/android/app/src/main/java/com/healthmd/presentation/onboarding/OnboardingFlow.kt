package com.healthmd.presentation.onboarding

import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan
import java.time.LocalDate

/** Onboarding v2: Welcome, Packs, Health Connect, Folder, First note, Make it daily. */
enum class OnboardingStep { WELCOME, PACKS, HEALTH, FOLDER, FIRST_NOTE, DAILY }

/**
 * Where the Daily note is written. Google Drive uses the connected Drive destination when this
 * build can connect Drive ([OnboardingUiState.usesDrive]); otherwise it is a folder chosen in the
 * system picker, so [target] is the fallback's device folder.
 */
enum class OnboardingDestination(val target: ExportTarget) {
    LOCAL_FOLDER(ExportTarget.DEVICE_FOLDER),
    API_ENDPOINT(ExportTarget.API_ENDPOINT),
    GOOGLE_DRIVE(ExportTarget.DEVICE_FOLDER),
}

/** What "Make it daily" offers on this channel and access state. */
enum class DailyOffer {
    /** Play without paid access: a store-billed trial or subscription. */
    TRIAL,
    /** F-Droid included access, or Play access already active: enable the schedule directly. */
    ENABLE,
}

/** Pure step rules shared by the screen and its tests. */
object OnboardingFlow {
    /** Name given to the existing default automation that onboarding configures. */
    const val DAILY_NOTE_NAME = "Daily note"
    const val DAILY_HOUR = 8
    const val DAILY_MINUTE = 0
    const val FIRST_NOTE_DAYS = 7L

    /** Progress dots cover the five setup steps; Make it daily has none. */
    const val PROGRESS_STEPS = 5

    fun next(step: OnboardingStep): OnboardingStep =
        OnboardingStep.entries.getOrElse(step.ordinal + 1) { OnboardingStep.DAILY }

    /** Make it daily follows a completed export, so it has no Back. */
    fun previous(step: OnboardingStep): OnboardingStep? = when (step) {
        OnboardingStep.WELCOME, OnboardingStep.DAILY -> null
        else -> OnboardingStep.entries[step.ordinal - 1]
    }

    fun progressIndex(step: OnboardingStep): Int? =
        if (step == OnboardingStep.DAILY) null else step.ordinal

    /** The last seven days, today included (Health Connect's default 30-day read window covers them). */
    fun firstNoteDates(today: LocalDate): List<LocalDate> =
        (FIRST_NOTE_DAYS - 1 downTo 0).map { today.minusDays(it) }

    fun dailyOffer(policy: DistributionPolicy, hasPaidAccess: Boolean): DailyOffer =
        if (policy.fullAccessIncluded || hasPaidAccess) DailyOffer.ENABLE else DailyOffer.TRIAL

    /** The yearly plan carries the 7-day trial; the live store price is the only price shown. */
    fun trialOffer(offers: List<PurchaseOffer>): PurchaseOffer? =
        offers.firstOrNull { it.plan == PurchasePlan.YEARLY && it.hasSevenDayTrial }
            ?: offers.firstOrNull { it.hasSevenDayTrial }

    fun canContinueFromPacks(selected: Int): Boolean = selected > 0

    /** "Google Drive/Health": the connected Drive folder as onboarding labels it. */
    fun driveLabel(folderLabel: String): String = "$DRIVE_LABEL/$folderLabel"

    private const val DRIVE_LABEL = "Google Drive"
}
