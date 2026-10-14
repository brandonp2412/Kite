package chat.schildi.revenge.compose.destination.conversation.event

import chat.schildi.lib.preferences.ScPrefs
import kotlin.test.Test
import kotlin.test.assertEquals

class MessageSwipeActionsTest {
    @Test
    fun legacyTouchDefaultsFollowCurrentMessagesGestures() {
        assertEquals(
            MessageSwipeConfig(
                left = ScPrefs.MessageSwipeAction.TIMESTAMPS,
                right = ScPrefs.MessageSwipeAction.REPLY,
            ),
            resolveMessageSwipeConfig(
                ScPrefs.MessageSwipeAction.REPLY.name,
                ScPrefs.MessageSwipeAction.NONE.name,
            ),
        )
    }

    @Test
    fun explicitCustomSwipePairIsPreserved() {
        assertEquals(
            MessageSwipeConfig(
                left = ScPrefs.MessageSwipeAction.REACT,
                right = ScPrefs.MessageSwipeAction.EDIT,
            ),
            resolveMessageSwipeConfig(
                ScPrefs.MessageSwipeAction.REACT.name,
                ScPrefs.MessageSwipeAction.EDIT.name,
            ),
        )
    }

    @Test
    fun currentMessagesDefaultsAreStable() {
        assertEquals(
            MessageSwipeConfig(
                left = ScPrefs.MessageSwipeAction.TIMESTAMPS,
                right = ScPrefs.MessageSwipeAction.REPLY,
            ),
            resolveMessageSwipeConfig(
                ScPrefs.MessageSwipeAction.TIMESTAMPS.name,
                ScPrefs.MessageSwipeAction.REPLY.name,
            ),
        )
    }
}
