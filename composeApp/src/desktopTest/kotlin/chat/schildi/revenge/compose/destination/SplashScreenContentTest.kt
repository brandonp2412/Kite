package chat.schildi.revenge.compose.destination

import chat.schildi.revenge.compose.components.shouldShowTransientLoading
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SplashScreenContentTest {
    @Test
    fun shortNavigationDoesNotFlashLoadingIndicator() {
        assertFalse(shouldShowTransientLoading(gracePeriodElapsed = false, forceVisible = false))
    }

    @Test
    fun sustainedLoadingIsVisibleAfterGracePeriod() {
        assertTrue(shouldShowTransientLoading(gracePeriodElapsed = true, forceVisible = false))
    }

    @Test
    fun failedLoadingCanForceImmediateVisibility() {
        assertTrue(shouldShowTransientLoading(gracePeriodElapsed = false, forceVisible = true))
    }
}
