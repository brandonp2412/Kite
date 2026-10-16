package chat.schildi.revenge.compose.destination.conversation.event.message

import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals

class StableTextMessageLayoutTest {
    @Test
    fun outgoingTextStatusSpaceIsReservedBeforeSendingAndAfterDelivery() {
        val delivered = TimestampOverlayContent("15:30", isEdited = false, isSending = false, sendError = null)
        val sending = delivered.copy(isSending = true)

        assertEquals(76.dp, reservedTextTimestampInset(isOwn = true, timestamp = delivered))
        assertEquals(76.dp, reservedTextTimestampInset(isOwn = true, timestamp = sending))
    }

    @Test
    fun incomingTextWithoutStatusHasNoExtraInset() {
        val received = TimestampOverlayContent("15:30", isEdited = false, isSending = false, sendError = null)
        assertEquals(0.dp, reservedTextTimestampInset(isOwn = false, timestamp = received))
        assertEquals(0.dp, reservedTextTimestampInset(isOwn = false, timestamp = null))
    }

    @Test
    fun editedTextHasReservedWidthFromFirstLayout() {
        val edited = TimestampOverlayContent("15:30", isEdited = true, isSending = false, sendError = null)
        assertEquals(116.dp, reservedTextTimestampInset(isOwn = true, timestamp = edited))
        assertEquals(116.dp, reservedTextTimestampInset(isOwn = false, timestamp = edited))
    }
}
