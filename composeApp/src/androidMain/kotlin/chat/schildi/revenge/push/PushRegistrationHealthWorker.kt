package chat.schildi.revenge.push

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import co.touchlab.kermit.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withTimeout
import java.util.concurrent.TimeUnit

/** Repairs missing Matrix server pushers even when Kite has not been opened recently. */
class PushRegistrationHealthWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        val success = withTimeout(90_000L) {
            AndroidPushRegistrationHandler.repairSavedRegistrations()
        }
        if (success) Result.success() else Result.retry()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        log.e("Push registration health check failed", e)
        Result.retry()
    }

    companion object {
        private val log = Logger.withTag("PushRegistrationHealthWorker")
        private const val WORK_NAME = "kite-push-registration-health"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<PushRegistrationHealthWorker>(30, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }
}
