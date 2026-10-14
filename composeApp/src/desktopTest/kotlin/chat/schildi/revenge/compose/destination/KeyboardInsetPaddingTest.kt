package chat.schildi.revenge.compose.destination

import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals

class KeyboardInsetPaddingTest {
    @Test
    fun keyboardShownKeepsTwelveDpGapAboveIme() {
        assertEquals(12.dp, imeAwareBottomPadding(24.dp, 280.dp))
        assertEquals(12.dp, imeAwareBottomPadding(24.dp, 25.dp))
        assertEquals(12.dp, imeAwareBottomPadding(24.dp, 24.dp))
    }

    @Test
    fun keyboardDismissalTransitionsContinuouslyIntoNavigationBarInset() {
        assertEquals(13.dp, imeAwareBottomPadding(24.dp, 23.dp))
        assertEquals(24.dp, imeAwareBottomPadding(24.dp, 12.dp))
        assertEquals(35.dp, imeAwareBottomPadding(24.dp, 1.dp))
        assertEquals(36.dp, imeAwareBottomPadding(24.dp, 0.dp))
    }

    @Test
    fun devicesWithoutNavigationInsetKeepComposerGap() {
        assertEquals(12.dp, imeAwareBottomPadding(0.dp, 0.dp))
        assertEquals(12.dp, imeAwareBottomPadding(0.dp, 240.dp))
    }
}
