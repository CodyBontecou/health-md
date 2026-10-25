package com.healthmd.diagnostics

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ExportWorker
import com.healthmd.data.scheduler.ScheduledProfileExportWorker
import io.mockk.Runs
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import io.mockk.mockkObject
import io.mockk.slot
import io.mockk.spyk
import io.mockk.unmockkObject
import io.mockk.verify
import java.lang.reflect.InvocationTargetException
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [32])
class NotificationDiagnosticsTest {
    @After fun cleanup() { unmockkObject(Diagnostics) }

    @Test fun profileChannelFailureRetainsOperationEvidence() {
        val operation = UUID.fromString("12345678-1234-1234-1234-123456789abc")
        val context = spyk(ApplicationProvider.getApplicationContext<Context>())
        val manager = mockk<NotificationManager>(relaxed = true)
        every { context.getSystemService(NotificationManager::class.java) } returns manager
        every { manager.createNotificationChannel(any()) } throws SecurityException("Synthetic private detail")
        val worker = mockk<ScheduledProfileExportWorker>(relaxed = true)
        every { worker.applicationContext } returns context
        every { worker.id } returns operation
        every { worker["showFailureNotification"](any<String>()) } answers { callOriginal() }
        mockkObject(Diagnostics)
        every { Diagnostics.record(any(), any()) } just Runs

        val method = ScheduledProfileExportWorker::class.java.getDeclaredMethod("showFailureNotification", String::class.java)
        method.isAccessible = true
        method.invoke(worker, "Synthetic profile")

        val fields = slot<Map<DiagnosticField, DiagnosticValue>>()
        verify(exactly = 1) { Diagnostics.record(DiagnosticEventID.NOTIFICATION_FAILED, capture(fields)) }
        assertThat(fields.captured[DiagnosticField.OPERATION_ID]).isEqualTo(DiagnosticValue.Text(operation.toString()))
        assertThat(fields.captured[DiagnosticField.ERROR_DOMAIN]).isEqualTo(DiagnosticValue.Text("SecurityException"))
        assertThat(fields.captured.values.toString()).doesNotContain("Synthetic private detail")
    }

    @Test fun ordinaryNotificationFailureRetainsOperationEvidenceAndStillThrows() {
        val operation = UUID.fromString("12345678-1234-1234-1234-123456789abc")
        val context = spyk(ApplicationProvider.getApplicationContext<Context>())
        val manager = mockk<NotificationManager>(relaxed = true)
        every { context.getSystemService(Context.NOTIFICATION_SERVICE) } returns manager
        every { manager.notify(any<Int>(), any()) } throws SecurityException("Synthetic private detail")
        val worker = mockk<ExportWorker>(relaxed = true)
        every { worker.applicationContext } returns context
        every { worker.id } returns operation
        every { worker["canPostNotifications"]() } returns true
        every { worker["showNotification"](any<String>(), any<String>(), any<String>(), any<Boolean>()) } answers { callOriginal() }
        mockkObject(Diagnostics)
        every { Diagnostics.record(any(), any()) } just Runs

        val method = ExportWorker::class.java.getDeclaredMethod("showNotification", String::class.java, String::class.java, String::class.java, Boolean::class.javaPrimitiveType)
        method.isAccessible = true
        assertThrows(InvocationTargetException::class.java) {
            method.invoke(worker, "Synthetic title", "Synthetic message", "schedule", false)
        }

        val fields = slot<Map<DiagnosticField, DiagnosticValue>>()
        verify(exactly = 1) { Diagnostics.record(DiagnosticEventID.NOTIFICATION_FAILED, capture(fields)) }
        assertThat(fields.captured[DiagnosticField.OPERATION_ID]).isEqualTo(DiagnosticValue.Text(operation.toString()))
        assertThat(fields.captured[DiagnosticField.ERROR_DOMAIN]).isEqualTo(DiagnosticValue.Text("SecurityException"))
        assertThat(fields.captured.values.toString()).doesNotContain("Synthetic private detail")
    }
}
