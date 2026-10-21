package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals

class StableTextMessageLayoutTest {
    @Test
    fun outgoingTextStatusSpaceIsReservedBeforeSendingAndAfterDelivery() {
        val delivered = TimestampOverlayContent(isEdited = false, isSending = false, sendError = null)
        val sending = delivered.copy(isSending = true)

        assertEquals(24.dp, reservedTextTimestampInset(isOwn = true, timestamp = delivered))
        assertEquals(24.dp, reservedTextTimestampInset(isOwn = true, timestamp = sending))
    }

    @Test
    fun multilineOutgoingMessageUsesFullWidthWithoutWrappingBeforeStatus() {
        val layout = stableTextTimestampPlacement(
            contentWidth = 320, contentHeight = 128, lastLineRight = 118,
            statusWidth = 76, statusHeight = 18, maxWidth = 320,
            horizontalGap = 8, verticalGap = 4,
        )
        assertEquals(320, layout.width)
        assertEquals(128, layout.height)
        assertEquals(244, layout.statusX)
        assertEquals(110, layout.statusY)
    }

    @Test
    fun multilineBubbleDoesNotIncludeUndrawnRightSideSpace() {
        assertEquals(260, stableTextBubbleWidth(320, 259.4f, tighten = true))
        assertEquals(320, stableTextBubbleWidth(320, 259.4f, tighten = false))
        assertEquals(320, stableTextBubbleWidth(320, null, tighten = true))
        assertEquals(320, stableTextBubbleWidth(320, 400f, tighten = true))
    }

    @Test
    fun fullLastLineGetsReservedStatusRowOnFirstMeasure() {
        val layout = stableTextTimestampPlacement(
            contentWidth = 320, contentHeight = 128, lastLineRight = 304,
            statusWidth = 76, statusHeight = 18, maxWidth = 320,
            horizontalGap = 8, verticalGap = 4,
        )
        assertEquals(320, layout.width)
        assertEquals(150, layout.height)
        assertEquals(244, layout.statusX)
        assertEquals(132, layout.statusY)
    }

    @Test
    fun shortMessagesReserveStatusOnLastLineWithoutGrowingHeight() {
        val layout = stableTextTimestampPlacement(
            contentWidth = 44, contentHeight = 24, lastLineRight = 44,
            statusWidth = 76, statusHeight = 18, maxWidth = 320,
            horizontalGap = 8, verticalGap = 4,
        )
        assertEquals(128, layout.width)
        assertEquals(24, layout.height)
        assertEquals(52, layout.statusX)
    }

    @Test
    fun incomingTextWithoutStatusHasNoExtraInset() {
        val received = TimestampOverlayContent(isEdited = false, isSending = false, sendError = null)
        assertEquals(0.dp, reservedTextTimestampInset(isOwn = false, timestamp = received))
        assertEquals(0.dp, reservedTextTimestampInset(isOwn = false, timestamp = null))
    }

    @Test
    fun editedTextHasReservedWidthFromFirstLayout() {
        val edited = TimestampOverlayContent(isEdited = true, isSending = false, sendError = null)
        assertEquals(56.dp, reservedTextTimestampInset(isOwn = true, timestamp = edited))
        assertEquals(56.dp, reservedTextTimestampInset(isOwn = false, timestamp = edited))
    }
}
