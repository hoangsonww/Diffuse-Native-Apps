package com.diffuse.android.core

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.diffuse.android.domain.Snapshot
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit

object CaptureSchedule {
    fun isDue(cadence: AndroidPreferences.Cadence, latestCapture: Instant?, now: Instant): Boolean {
        val hours = cadence.hours ?: return false
        return latestCapture == null || !now.isBefore(latestCapture.plus(hours, ChronoUnit.HOURS))
    }
}

class SnapshotWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = runCatching {
        val service = DiffuseService(applicationContext)
        service.capture(Snapshot.Origin.SCHEDULED, skipIfUnchanged = service.preferences.skipUnchanged)
        Result.success()
    }.getOrElse { Result.retry() }

    companion object {
        private const val name = "diffuse.periodic-snapshot"

        fun schedule(context: Context, cadence: AndroidPreferences.Cadence) {
            val manager = WorkManager.getInstance(context)
            val hours = cadence.hours
            if (hours == null) {
                manager.cancelUniqueWork(name)
                return
            }
            val request = PeriodicWorkRequestBuilder<SnapshotWorker>(hours, TimeUnit.HOURS).build()
            manager.enqueueUniquePeriodicWork(name, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
