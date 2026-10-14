package chat.schildi.revenge.compose.destination

import chat.schildi.revenge.model.CheckpointLoadState
import chat.schildi.revenge.model.LoadCheckPoint
import chat.schildi.revenge.model.LoadStateEntry
import kotlinx.collections.immutable.persistentListOf
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SplashScreenContentTest {
    @Test
    fun shortNavigationDoesNotFlashLoadingIndicator() {
        assertFalse(shouldShowLoadingIndicator(gracePeriodElapsed = false, loadState = null))
        assertFalse(
            shouldShowLoadingIndicator(
                gracePeriodElapsed = false,
                loadState = persistentListOf(LoadStateEntry(LoadCheckPoint.Timeline, CheckpointLoadState.PENDING)),
            )
        )
    }

    @Test
    fun sustainedLoadingIsVisibleAfterGracePeriod() {
        assertTrue(shouldShowLoadingIndicator(gracePeriodElapsed = true, loadState = null))
        assertTrue(
            shouldShowLoadingIndicator(
                gracePeriodElapsed = true,
                loadState = persistentListOf(LoadStateEntry(LoadCheckPoint.Timeline, CheckpointLoadState.PENDING)),
            )
        )
    }

    @Test
    fun failedLoadingIsVisibleImmediately() {
        assertTrue(
            shouldShowLoadingIndicator(
                gracePeriodElapsed = false,
                loadState = persistentListOf(LoadStateEntry(LoadCheckPoint.Timeline, CheckpointLoadState.FAILED)),
            )
        )
    }
}
