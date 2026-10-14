package chat.schildi.revenge

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals

class MessageBubbleShapeTest {
    @Test
    fun standaloneBubbleKeepsFullRadius() {
        assertEquals(
            RoundedCornerShape(20.dp),
            Dimens.Conversation.messageBubbleShape(
                isOwn = false,
                joinsPrevious = false,
                joinsNext = false,
            ),
        )
    }

    @Test
    fun incomingRunConnectsOnLeadingEdge() {
        assertEquals(
            RoundedCornerShape(
                topStart = 6.dp,
                topEnd = 20.dp,
                bottomStart = 6.dp,
                bottomEnd = 20.dp,
            ),
            Dimens.Conversation.messageBubbleShape(
                isOwn = false,
                joinsPrevious = true,
                joinsNext = true,
            ),
        )
    }

    @Test
    fun outgoingRunConnectsOnTrailingEdge() {
        assertEquals(
            RoundedCornerShape(
                topStart = 20.dp,
                topEnd = 6.dp,
                bottomStart = 20.dp,
                bottomEnd = 6.dp,
            ),
            Dimens.Conversation.messageBubbleShape(
                isOwn = true,
                joinsPrevious = true,
                joinsNext = true,
            ),
        )
    }
}
