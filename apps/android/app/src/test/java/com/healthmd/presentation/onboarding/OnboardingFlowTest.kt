package com.healthmd.presentation.onboarding

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.presentation.export.ExportUiState
import java.time.LocalDate
import org.junit.Test

class OnboardingFlowTest {
    @Test
    fun stepsRunWelcomeToMakeItDailyWithoutAReadyOrAccessPage() {
        assertThat(OnboardingStep.entries).containsExactly(
            OnboardingStep.WELCOME, OnboardingStep.PACKS, OnboardingStep.HEALTH,
            OnboardingStep.FOLDER, OnboardingStep.FIRST_NOTE, OnboardingStep.DAILY,
        ).inOrder()
        assertThat(OnboardingFlow.next(OnboardingStep.HEALTH)).isEqualTo(OnboardingStep.FOLDER)
        assertThat(OnboardingFlow.next(OnboardingStep.DAILY)).isEqualTo(OnboardingStep.DAILY)
    }

    @Test
    fun backIsUnavailableOnWelcomeAndAfterTheExport() {
        assertThat(OnboardingFlow.previous(OnboardingStep.WELCOME)).isNull()
        assertThat(OnboardingFlow.previous(OnboardingStep.DAILY)).isNull()
        assertThat(OnboardingFlow.previous(OnboardingStep.FIRST_NOTE)).isEqualTo(OnboardingStep.FOLDER)
        assertThat(OnboardingFlow.progressIndex(OnboardingStep.DAILY)).isNull()
        assertThat(OnboardingFlow.progressIndex(OnboardingStep.FIRST_NOTE)).isEqualTo(OnboardingFlow.PROGRESS_STEPS - 1)
    }

    @Test
    fun firstNoteCoversTheLastSevenDaysIncludingToday() {
        val dates = OnboardingFlow.firstNoteDates(LocalDate.of(2026, 11, 12))
        assertThat(dates.first()).isEqualTo(LocalDate.of(2026, 11, 6))
        assertThat(dates.last()).isEqualTo(LocalDate.of(2026, 11, 12))
        assertThat(dates).hasSize(7)
    }

    @Test
    fun playOffersTheTrialUntilPaidAccessAndFdroidEnablesDirectly() {
        val play = DistributionPolicy.play()
        assertThat(OnboardingFlow.dailyOffer(play, hasPaidAccess = false)).isEqualTo(DailyOffer.TRIAL)
        assertThat(OnboardingFlow.dailyOffer(play, hasPaidAccess = true)).isEqualTo(DailyOffer.ENABLE)
        assertThat(OnboardingFlow.dailyOffer(DistributionPolicy.fdroid(), hasPaidAccess = false)).isEqualTo(DailyOffer.ENABLE)
        // Unavailable billing never enables a schedule without access.
        assertThat(OnboardingFlow.dailyOffer(play.copy(purchasesAvailable = false), hasPaidAccess = false))
            .isEqualTo(DailyOffer.TRIAL)
    }

    @Test
    fun trialUsesTheLiveYearlyTrialOffer() {
        val weekly = PurchaseOffer("w", "$1.99", PurchasePlan.WEEKLY)
        val yearly = PurchaseOffer("y", "$29.99", PurchasePlan.YEARLY, hasSevenDayTrial = true)
        assertThat(OnboardingFlow.trialOffer(listOf(weekly, yearly))).isEqualTo(yearly)
        assertThat(OnboardingFlow.trialOffer(listOf(weekly))).isNull()
        assertThat(OnboardingFlow.trialOffer(emptyList())).isNull()
    }

    @Test
    fun firstNoteActionUsesTheFreeExportOnlyForRealNotes() {
        val dates = OnboardingFlow.firstNoteDates(LocalDate.of(2026, 11, 12))
        val sample = OnboardingUiState(
            note = NotePreviewState.Sample(SampleReason.NO_DATA, OnboardingSampleNote.days(dates, setOf())),
            folderUri = "content://tree", folderName = "Obsidian",
        )
        val freeLeft = ExportUiState(freeExportsRemaining = 1, isPurchased = false)
        assertThat(firstNoteAction(sample, freeLeft)).isEqualTo(FirstNoteAction.Finish)

        val days = dates.mapIndexed { i, d -> OnboardingNoteDay(d, raw = if (i % 2 == 0) "x" else null) }
        val ready = sample.copy(note = NotePreviewState.Ready(days))
        assertThat(firstNoteAction(ready, freeLeft))
            .isEqualTo(FirstNoteAction.Save(count = 4, destination = "Obsidian/health", sends = false))
        assertThat(firstNoteAction(ready, ExportUiState(freeExportsRemaining = 0, isPurchased = false)))
            .isEqualTo(FirstNoteAction.FreeUsed)
        assertThat(firstNoteAction(ready.copy(folderUri = null), freeLeft)).isEqualTo(FirstNoteAction.ChooseFolder)

        // API destination: send to the saved endpoint with the same free export, else finish.
        val api = ready.copy(destination = OnboardingDestination.API_ENDPOINT)
        assertThat(firstNoteAction(api, freeLeft)).isEqualTo(FirstNoteAction.Finish)
        val endpoint = com.healthmd.domain.model.SavedAPIEndpoint("e", "Home server", "https://api.example.com/health")
        assertThat(firstNoteAction(api.copy(apiEndpoint = endpoint), freeLeft))
            .isEqualTo(FirstNoteAction.Save(count = 4, destination = "Home server", sends = true))
    }
}
