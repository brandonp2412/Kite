package chat.schildi.revenge.model.conversation

import io.element.android.libraries.matrix.api.core.UniqueId
import io.element.android.libraries.matrix.api.timeline.MatrixTimelineItem
import io.element.android.libraries.matrix.api.timeline.item.event.RedactedContent
import io.element.android.libraries.matrix.api.timeline.item.event.UnknownContent
import io.element.android.libraries.matrix.api.timeline.item.virtual.VirtualTimelineItem
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class KiteTimelineVisibilityTest {
    @Test
    fun dateDividersFromHiddenServerEventsNeverReachTheList() {
        val orphanDate = MatrixTimelineItem.Virtual(
            UniqueId("orphan-date"),
            VirtualTimelineItem.DayDivider(1_700_000_000_000L),
        )
        val loading = MatrixTimelineItem.Virtual(
            UniqueId("pagination"),
            VirtualTimelineItem.RoomBeginning,
        )
        val items = listOf(orphanDate, MatrixTimelineItem.Other, loading)

        assertEquals(listOf(loading), items.filter { it.isKiteVisibleConversationItem() })
    }

    @Test
    fun serverEventsStayHiddenWithoutHidingMessagePlaceholders() {
        assertFalse(UnknownContent.isKiteVisibleMessageContent())
        assertTrue(RedactedContent(null).isKiteVisibleMessageContent())
    }
}
