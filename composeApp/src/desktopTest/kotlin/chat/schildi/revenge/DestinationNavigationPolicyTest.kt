package chat.schildi.revenge

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DestinationNavigationPolicyTest {
    @Test
    fun mobileInboxConversationNavigationStaysInCurrentWindow() {
        assertTrue(
            shouldNavigateInCurrentWindow(
                currentCategory = DestinationCategory.INBOX,
                destinationCategory = DestinationCategory.CONVERSATION,
                appOwnsWindows = false,
            )
        )
    }

    @Test
    fun androidChatBackAndOtherNormalNavigationNeverLaunchAnotherActivity() {
        for ((from, to) in listOf(
            DestinationCategory.CONVERSATION to DestinationCategory.INBOX,
            DestinationCategory.CONVERSATION to DestinationCategory.SETTINGS,
            DestinationCategory.SETTINGS to DestinationCategory.INBOX,
        )) {
            assertTrue(shouldNavigateInCurrentWindow(from, to, appOwnsWindows = false))
        }
    }

    @Test
    fun desktopInboxConversationNavigationKeepsSeparateWindowBehavior() {
        assertFalse(
            shouldNavigateInCurrentWindow(
                currentCategory = DestinationCategory.INBOX,
                destinationCategory = DestinationCategory.CONVERSATION,
                appOwnsWindows = true,
            )
        )
    }

    @Test
    fun explicitSameCategoryNavigationAlwaysStaysInCurrentWindow() {
        assertTrue(
            shouldNavigateInCurrentWindow(
                currentCategory = DestinationCategory.CONVERSATION,
                destinationCategory = DestinationCategory.CONVERSATION,
                appOwnsWindows = true,
            )
        )
    }
}
