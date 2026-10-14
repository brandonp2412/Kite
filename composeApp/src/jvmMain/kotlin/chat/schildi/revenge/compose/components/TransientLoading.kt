package chat.schildi.revenge.compose.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay

internal const val TransientLoadingGracePeriodMillis = 650L

/**
 * Avoid painting progress chrome for work that completes within a few frames.
 *
 * This is intentionally state-only so callers can reserve stable layout space while
 * delaying the visual indicator, preventing both spinner flashes and late remeasure jolts.
 */
@Composable
fun rememberTransientLoadingVisible(
    forceVisible: Boolean = false,
    delayMillis: Long = TransientLoadingGracePeriodMillis,
): Boolean {
    var gracePeriodElapsed by remember(delayMillis) { mutableStateOf(delayMillis <= 0L) }
    LaunchedEffect(delayMillis) {
        if (delayMillis > 0L) {
            delay(delayMillis)
            gracePeriodElapsed = true
        }
    }
    return shouldShowTransientLoading(gracePeriodElapsed, forceVisible)
}

internal fun shouldShowTransientLoading(
    gracePeriodElapsed: Boolean,
    forceVisible: Boolean,
): Boolean = forceVisible || gracePeriodElapsed
